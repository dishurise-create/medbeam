# Turning on community reports (Supabase)

Without this, each iPhone only sees its own reports. With it, every RxRadar user's
anonymous "had it / didn't" answers help everyone nearby. It's free.

## 1. Create the database (about 5 minutes)
1. Go to https://supabase.com and sign up (free plan, no credit card).
2. Click **New project**. Name it `rxradar`, pick a strong database password
   (save it somewhere; the app never needs it), choose the **East US** region.
3. Wait about a minute for the project to finish setting up.

## 2. Create the reports table
1. In the left sidebar, open **SQL Editor** → **New query**.
2. Open `backend/supabase-setup.sql` from this folder, copy everything, paste it in.
3. Click **Run**. You should see "Success. No rows returned."

This creates one table and locks it down so the app can only **read recent reports**
and **add new ones**. Nobody using the app can edit or delete reports. It also
limits spam (max 3 reports per minute per pharmacy).

## 3. Connect the app
1. In Supabase, open **Project Settings** → **API Keys** (or **Connect**).
2. Copy the **Project URL** (looks like `https://abcdefgh.supabase.co`).
3. Copy the **publishable key** (starts with `sb_publishable_`). On older projects,
   use the **anon public** key instead.
   ⚠️ Never use the **secret** / **service_role** key in the app.
4. In Xcode, open `RxRadar/Config/BackendConfig.swift` and paste them:
   ```swift
   static let supabaseURL = "https://abcdefgh.supabase.co"
   static let supabasePublishableKey = "sb_publishable_..."
   ```
5. Run the app. **Settings → Data → Community sharing** should say **On**.

## 4. Check it works
1. Search any medication and ZIP, open a pharmacy, and report "had it".
2. In Supabase, open **Table Editor → reports**. Your report should be there
   (only medication ID, location, in_stock, time).
3. On a second phone or simulator, search the same medication near there and
   pull down on the results list. The report counts in that pharmacy's estimate.

## Is the key safe to put in the app?
Yes. The publishable key is meant to be public; it can only do what the rules in
`supabase-setup.sql` allow. The secret key is the one to keep private.

## Free plan limits
Plenty for this project (500 MB database, which is millions of reports). Free
projects pause after 1 week with no activity; open the Supabase dashboard and click
**Restore** if that happens (check this before judging!).
