# Running the app in a Claude Code sandbox

`README.md` covers normal local setup. This file records what is different in the remote
sandbox, because several things are not obvious and cost real time to rediscover.

`.claude/hooks/session-start.sh` already installs Ruby, MySQL and Redis and prepares the test
database, so a fresh session can run RSpec without any manual setup.

## What works and what does not

| Service | Status |
| --- | --- |
| Ruby (the version in `.ruby-version`) | Installed from the prebuilt tarball `ruby/ruby-builder` publishes on GitHub, because `rbenv install` fetches from `cache.ruby-lang.org`, which the network policy blocks |
| MySQL | `apt-get install mysql-server` |
| Redis | Preinstalled |
| Elasticsearch | **Unavailable** — `artifacts.elastic.co` and `docker.io` are blocked and it is not in apt |
| MongoDB | **Unavailable** — `fastdl.mongodb.org`, `repo.mongodb.org` and `docker.io` are blocked and it is not in apt |

MongoDB's absence is the one that shapes testing. `User` validation calls
`BlockedObject.find_object`, which is Mongoid-backed
(`app/models/concerns/attribute_blockable.rb`), so **any spec calling `create(:user)` fails** with
`Mongo::Error::NoServerAvailable`, and by default burns a 30 second driver timeout first. A run
that looks hung is usually this.

Two ways to work around it in a spec you are writing:

- `build(:user)` instead of `create(:user)` where the spec only needs an in-memory association.
  `build` skips validation, so it never reaches Mongo. `spec/models/seller_profile_links_section_spec.rb`
  does this and runs green in the sandbox.
- Drop `server_selection_timeout: 1` into the `test` client options in `config/mongoid.yml`
  **locally, without committing it**, so Mongo-dependent examples fail in a second rather than
  thirty. That makes it practical to run a large money-path spec file and check whether any
  failure is something other than `Mongo::Error` — which is the only regression signal available
  here for code that touches purchases.

## Booting the app

```bash
bin/rails db:create db:schema:load     # development database
bin/shakapacker                        # JS bundle; pages render blank without it
bin/rails server -p 3000 -b 127.0.0.1
```

The app boots and serves pages without Elasticsearch or MongoDB.

## Hostnames matter more than ports

Most routes live inside `GumroadDomainConstraint`, which matches on `VALID_REQUEST_HOSTS`
(`app.gumroad.dev` and `gumroad.dev`). A request to `127.0.0.1:3000` gets `No route matches`, which
looks like a routing bug and is not one.

Creator profiles are served from a **subdomain**, not a path: `/:username` on the app host issues a
301 to `https://<username>.gumroad.dev`. So map the hosts first:

```bash
echo "127.0.0.1 gumroad.dev app.gumroad.dev <username>.gumroad.dev" >> /etc/hosts
```

Then `http://app.gumroad.dev:3000` is the dashboard and `http://<username>.gumroad.dev:3000` is that
creator's profile.

One more wrinkle for headless browsers: the page references its assets at `https://app.gumroad.dev`
(port 443) while the server listens on plain HTTP 3000, so a browser loads the HTML and then fails
every asset. Either terminate TLS on 443 or, more simply, intercept those requests in the browser
driver and refetch them from `http://app.gumroad.dev:3000`.

## Seeding a creator to click through

`create(:user)` needs Mongo, so save the user without validation:

```ruby
user = User.new(email: "demo@example.com", username: "gummydemo",
                password: "-42Q_.c_3628Ca!mW-xTJ8v*", confirmed_at: Time.current,
                user_risk_state: "not_reviewed", name: "Gummy Demo")
user.save!(validate: false)

# Sign-in stops at the 2FA step otherwise.
user.two_factor_authentication_enabled = false
user.save!(validate: false)

profile = user.seller_profile || user.create_seller_profile!
section = SellerProfileLinksSection.create!(seller: user, header: "Find me everywhere",
                                            json_data: { "links" => [] })
profile.update!(json_data: { "tabs" => [{ "name" => "Home", "sections" => [section.id] }] })
```

A section that is not listed in a tab exists but never renders, which is a confusing way to lose
half an hour.

## A trap worth knowing

`crypto.randomUUID()` is only defined in a secure context. Over plain HTTP in the sandbox it is
`undefined`, so any handler calling it throws and the UI silently does nothing. Use
`$app/utils/guid_generator`, which the profile editor already uses. This class of bug is invisible
to `tsc`, `eslint` and model specs, and only shows up when the app is actually driven in a browser.
