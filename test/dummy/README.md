# Recording Studio Webhooks Dummy App

This host application validates the mounted inbound-only webhook engine with
Devise, Recording Studio, PostgreSQL UUID migrations, and FlatPack.

```bash
cd test/dummy
bundle install
bin/rails db:prepare
bin/dev
```

Sign in as `admin@admin.com` with password `Password`, then open
**Webhook endpoints**. The dummy seeds a stable Recording Studio recording and
a `demo` endpoint. Its dispatcher is intentionally a no-op, so the browser
demo never executes actions or sends network requests.

Useful routes:

- `/` — dummy overview;
- `/webhooks/admin/endpoints` — engine administration;
- `/webhooks/inbound/:provider/:endpoint_key` — public JSON intake;
- `/users/sign_in` — Devise sign-in; and
- `/up` — Rails health check.
