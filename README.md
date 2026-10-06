# Pouch – shared lists

A small web app for shared lists. Each list has its own link and password. Tap an item to cross it off, and everyone with the list open sees the change straight away. Lists remember what was typed before and suggest it again.

It is two files:

- `index.html` – the whole app. Hosted for free on GitHub Pages.
- `setup.sql` – creates the database in Supabase (free, open-source).

Setup takes about 10 minutes.

---

## 1. Create the database (Supabase)

1. Go to <https://supabase.com>, sign up for free, and click **New project**. Pick any name, a database password (you won't need it again), and the region closest to you (e.g. Stockholm or Frankfurt).
2. When the project is ready, open **SQL Editor** in the left menu, click **New query**, paste the whole contents of `setup.sql`, and press **Run**. It should say "Success. No rows returned".
3. Open **Project Settings → API Keys** (or **Connect**) and copy two values:
   - the **Project URL**, like `https://abcdefgh.supabase.co`
   - the **publishable key** (starts with `sb_publishable_`). On older projects it's called the **anon public** key. Never use the `service_role` / secret key.

## 2. Put your values in the app

Open `index.html` in any text editor and find this near the top:

```js
const SUPABASE_URL = "https://YOUR-PROJECT.supabase.co";
const SUPABASE_KEY = "YOUR-ANON-OR-PUBLISHABLE-KEY";
```

Paste in your two values and save. The public key is meant to be visible in web pages. It can't read the tables directly; it can only call the list functions, and those check the list's password first.

## 3. Publish on GitHub Pages

1. Sign in at <https://github.com> and create a **new repository**, e.g. `lists`. Make it **Public** (free Pages needs that; your list data stays in Supabase, not in the repo).
2. Click **Add file → Upload files** and upload `index.html`. Commit.
3. Go to **Settings → Pages**. Under **Build and deployment**, choose **Deploy from a branch**, branch **main**, folder **/ (root)**, and save.
4. After a minute your app is live at `https://YOUR-USERNAME.github.io/lists/`.

Tip: on your phone, open that address and use **Add to Home Screen** so it opens like an app.

---

## Using it

- **New list:** type a name and a password on the start page.
- **Share:** tap the share icon. The link includes the password, so whoever taps it gets straight in and their phone remembers the list.
- **Add several at once:** separate items with commas, like `2 milk, bread, 200g cheese`, or paste a list with one item per line.
- **Cross off:** tap an item. Tap a crossed-off item to bring it back.
- **Amounts:** type them in front of the item, like `2 milk`, `200g blueberries` or `three apples`. Items without an amount get 1. Tap the amount on an item to change it.
- **People:** the first time you open a list, it asks for your name. Everyone who has opened the list shows at the top, with a green dot when they have it open right now. Tap your own name to change it. Once two or more people use a list, each item shows the initial of whoever added it, or whoever crossed it off.
- **Undo:** deleting an item (×) or clearing the crossed-off pile shows an **Undo** button for a few seconds.
- **Suggestions:** as you type, earlier items from that list show up as chips. With the box empty, the most-used items show. Tap × on a chip to forget it.
- **Crossed-off items (⋯ menu):**
  - **Hide it** (default): crossed-off items go into a pile at the bottom, hidden until you tap **Show**. **Clear** deletes the pile.
  - **Delete it:** crossed-off items are deleted after about 3 seconds, with an **Undo** button.
- **List settings (⋯ menu):** rename the list, change its password, or delete it for everyone. Changing the password locks everyone else out until you share the list again with the new link; it's also the way to remove someone's access.
- **Remove from this phone (⋯ menu):** takes the list off your start page. The list itself stays, and the share link still works.

## Good to know

- **Security level:** fine for groceries and chores, not for secrets. Anyone with the link and password can change or delete items. List links contain a long random code, so they can't be guessed.
- **Keeping the database awake:** free Supabase projects pause after about a week without use. A scheduled job in this repo (`.github/workflows/keep-awake.yml`) pings the database every 3 days so that doesn't happen. GitHub switches scheduled jobs off in repos with no changes for 60 days and sends you an email; re-enable it under the repo's **Actions** tab. If the app ever says it can't connect, open the Supabase dashboard and press **Restore project**.
- **Live updates** use Supabase Realtime. If changes only show up after about 30 seconds instead of instantly, open **Realtime → Settings** in Supabase and make sure public channel access is allowed. The app also refreshes whenever you switch back to it.
