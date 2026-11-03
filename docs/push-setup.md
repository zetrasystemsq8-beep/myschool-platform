# Phone push notifications: setup

How it works: when the database creates an in-app notification (a notice, meeting, message or report), a Supabase **Database Webhook** calls the
`myschool-send-push` Edge Function, which sends it to the person's phones through Firebase. The same notification still appears inside the app.
Phones register their Firebase token when someone signs in, and remove it when they sign out.

## 1. Database
Run `supabase/migrations/20260101000019_device_tokens.sql` once in the SQL Editor.

## 2. Create the sending key (Firebase)
Firebase console > your project > gear icon > **Project settings** > **Service accounts** > **Generate new private key**. A `.json` file downloads.
**This file is a password. Never put it in GitHub, the app or a chat.** You will paste its content into Supabase in step 3 and then delete the file.

## 3. Supabase secrets (Edge Functions > Secrets)
- `FCM_SERVICE_ACCOUNT` = the whole content of the downloaded `.json` file
- `PUSH_WEBHOOK_SECRET` = any long random text. In Termux you can make one: `head -c 24 /dev/urandom | base64`

## 4. Deploy the function
Edge Functions > Deploy a new function > name `myschool-send-push` > paste `myschool-send-push.ts` > **turn Verify JWT OFF** > deploy.

## 5. Create the webhook
Supabase > Database > **Webhooks** > Create a new hook:
- Name: `push_notifications`
- Table: `notifications` in schema `myschool`
- Events: **Insert** and **Update**
- Type: HTTP Request, method POST
- URL: `https://<your-project-ref>.supabase.co/functions/v1/myschool-send-push`
- HTTP headers: add `x-webhook-secret` with the same value as `PUSH_WEBHOOK_SECRET`

## 6. Try it
Install the new app on two phones (or one phone and sign in as a parent), sign in, and allow notifications when asked.
As the school admin publish a notice for everyone. The other phone should show a notification even with the app closed; tapping it opens Notices.
If nothing arrives: check Edge Functions > myschool-send-push > Logs, and that the person signed in on that phone after installing the new app.

## Notes
- Not sent by push (by design, to avoid noise): attendance, fees, results.
- A second unread message in the same conversation updates the existing notification instead of buzzing again.
- iPhone is not set up (no Apple account); only Android.
