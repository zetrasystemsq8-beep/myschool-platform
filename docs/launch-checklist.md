# Launch checklist

Do these in order. Tick each one.

## 1. Use a dedicated Supabase project for real schools
The current project is shared with your other apps. Before real schools use MySchool, create a **new Supabase project** just for it,
run all migrations in order (1 to 18), expose the `myschool` schema (Settings > API > Exposed schemas), create the platform admin, deploy the two
Edge Functions, and point the app at it (`app/lib/config.dart`: URL and anon key). Never run `seed.sql` there.
- Choose a paid plan before launch: free projects pause after a week without activity and have no automatic daily backups you can rely on.
- Run `supabase/scripts/verify_production.sql` in that project. Every line must say OK.

## 2. Create the signing key (once) and add it to GitHub
Install Java in Termux and make the key. **Back up the .jks file and both passwords somewhere safe. Losing them can lock you out of updating the app.**
```bash
pkg install -y openjdk-17
keytool -genkeypair -v -keystore ~/myschool-upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
base64 -w0 ~/myschool-upload.jks > ~/myschool-upload.b64
```
On GitHub: repo > Settings > Secrets and variables > Actions > New repository secret. Add four secrets:
`ANDROID_KEYSTORE_BASE64` (the whole text inside myschool-upload.b64), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS` (= `upload`).
Then: Actions > **release-android** > Run workflow. Download the artifact `myschool-release`: it holds `app-release.aab` (for Google Play) and a signed APK.
The step "Show who signed the bundle" must NOT say "Android Debug".
Enroll in **Play App Signing** when you upload (Google keeps the final key; your key is only the upload key, so it can be reset if lost).
**The app ID is `com.myschool.myschool_app`. It can never be changed after the first upload.** To change it, edit `--org` in `.github/workflows/release.yml` first.

## 3. Privacy policy and terms (Google requires a public link)
1. Fill in your details (run from the repo folder, replace the values):
   ```bash
   sed -i 's/{{OWNER_NAME}}/Your Business Name/g; s/{{CONTACT_EMAIL}}/you@yourdomain.com/g; s/{{DATE}}/1 January 2027/g' docs/privacy.html docs/terms.html
   sed -i "s/YOUR-EMAIL@example.com/you@yourdomain.com/; s/YOUR-GITHUB-NAME/zetrasystemsq8-beep/g" app/lib/config.dart
   ```
2. GitHub repo > Settings > Pages > Source: **Deploy from a branch**, branch `main`, folder `/docs`. Your links become
   `https://zetrasystemsq8-beep.github.io/myschool-platform/privacy.html` and `.../terms.html`.
3. Have a lawyer read both documents before you publish. They are a careful draft, not legal advice.

## 4. Supabase production settings (Dashboard)
- Authentication > Providers > Email: confirm email ON for staff/parents is optional (accounts are admin-created), set **minimum password length 8 or more**.
- Authentication > Attack protection: enable **CAPTCHA** and leave the sign-in rate limits on.
- Authentication > URL configuration: set the Site URL to your privacy page or website (not localhost).
- Edge Functions: `myschool-student-login` has Verify JWT **OFF** (it is the sign-in itself); `myschool-provision-user` has it **ON**. Paste the new `myschool-student-login.ts` (it adds the PIN lockout) and apply migration 18.
- Database > Backups: turn on daily backups (and PITR if your plan allows). Do a trial restore once.
- Never put the service-role key in the app, GitHub, chats or screenshots. If it was ever shared, rotate it (Settings > API).

## 5. Google Play
- Create a Play developer account (one-time fee). A **new personal account must run a closed test with at least 12 testers for 14 days** before it can publish to production (Google's rule at the time of writing; check the Play Console). An organisation account is exempt.
- Store listing: name MySchool, short and full description, icon (512x512, use `app/assets/icon/icon.png`), at least 2 phone screenshots, feature graphic (1024x500).
- App content: privacy policy URL (step 3), data safety form (answers below), content rating questionnaire, target audience (set to adults and teens/children as appropriate with the school context), ads: **no ads**.
- Account deletion: the app explains how (Profile > Privacy, terms and deleting my data). Also put the same web page/email in the Play "account deletion" field.

### Data safety answers
| Question | Answer |
|---|---|
| Data collected | Name, email address, user IDs (admission number), other info (grades, attendance, fee records), messages, photos (school logo only) |
| Data shared with third parties | None (Supabase acts as our service provider) |
| Encrypted in transit | Yes |
| Users can request deletion | Yes (through the school or by email) |
| Ads / tracking / analytics | None |
| Location, contacts, financial/card info | Not collected |

## 6. Before saying "live"
- [ ] `verify_production.sql` all OK in the production project
- [ ] The release-android run is green and the signer is not "Android Debug"
- [ ] A real phone test: create school, admin, class, teacher, student, result > approve > share > student sees it
- [ ] Student PIN lockout works (5 wrong tries, then the 15-minute message)
- [ ] Privacy and terms pages open from the public links
- [ ] Keystore and passwords backed up in two places
