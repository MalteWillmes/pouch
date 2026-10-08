# Pouch – shared topics and lists

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

- **Topics and lists:** a *topic* (e.g. "Shopping") is what you share: it has the link and password, the people, the categories and everything the app remembers. Inside a topic you make *lists*, e.g. one per shopping trip.
- **New topic:** type your name, a topic name and a password on the start page. Its first list (named with today's date) opens straight away.
- **New list:** on the topic screen tap **+ New list**. It's named with today's date (rename it if you like). If the newest open list still has unbought items, it asks whether to move them to the new list (it names them), and you choose **Move them** or **Leave them**.
- **History:** a list where everything is crossed off moves to **History** on the topic screen automatically, showing what was bought on that trip. Open it any time; adding something or bringing an item back reopens it.
- **List menu (⋯ on a list):** rename or delete the list, open Categories, or jump to the topic's settings.
- **Share:** tap the share icon. The link includes the password, so whoever taps it gets straight into the topic's newest list, and their phone remembers the topic.
- **Add several at once:** separate items with commas, like `2 milk, bread, 200g cheese`, or paste a list with one item per line.
- **Cross off:** tap an item. Tap a crossed-off item to bring it back.
- **Amounts:** type them in front of the item, like `2 milk`, `200g blueberries` or `three apples`. Items without an amount get 1. Tap the amount on an item to change it.
- **People:** the first time you open a list, it asks for your name. Everyone who has opened the list shows at the top, with a green dot when they have it open right now. Tap your own name to change it. Once two or more people use a list, each item shows the initial of whoever added it, or whoever crossed it off.
- **Undo:** deleting an item (×) or clearing the crossed-off pile shows an **Undo** button for a few seconds.
- **Categories:** when you make a list, pick starter grocery categories (Norwegian, German or English names), copy the categories from another of your lists, or none. Items get their categories automatically from a word list in all three languages; the categories show as small tags under each item. Tap a tag (or **+ category**) to change them or make a new one; the list remembers your choice the next time that item is added. An item can have several.
- **Order and filtering:** the list follows the category order. Change it under **⋯ → Categories**: drag ⠿ to move a category, tap a name to rename it, × to delete it. Tap a category in the row above the list to show only those items.
- **Sorting:** the small **Sort** menu above the list sorts open items by category (default), A–Z, by person (A–Z by name), or by time added. The choice is shared: changing it changes the order for everyone on the list.
- **Copy list:** the **Copy list** button above the list copies the open items as plain text (list name, then one `- 2 milk` line per item) so you can paste it into a text message. It follows the current sort, and if a category filter is on, only that category is copied.
- **Suggestions:** as you type, earlier items from that list show up as chips. With the box empty, the most-used items show. Tap × on a chip to forget it.
- **Crossed-off items (topic ⋯ menu):**
  - **Hide it** (default): crossed-off items stay at the bottom of their list (and in History). **Clear** deletes them.
  - **Delete it:** crossed-off items are deleted after about 3 seconds, with an **Undo** button, so lists keep no history.
- **Topic settings (⋯ on the topic screen):** rename the topic, change its password, or delete it for everyone. Changing the password locks everyone else out until you share the list again with the new link; it's also the way to remove someone's access.
- **Remove from this phone (topic ⋯ menu):** takes the topic off your start page. The topic itself stays, and the share link still works.

## Good to know

- **Security level:** fine for groceries and chores, not for secrets. Anyone with the link and password can change or delete items. List links contain a long random code, so they can't be guessed.
- **Keeping the database awake:** free Supabase projects pause after about a week without use. A scheduled job in this repo (`.github/workflows/keep-awake.yml`) pings the database every 3 days so that doesn't happen. GitHub switches scheduled jobs off in repos with no changes for 60 days and sends you an email; re-enable it under the repo's **Actions** tab. If the app ever says it can't connect, open the Supabase dashboard and press **Restore project**.
- **App updates:** phones that keep Pouch open (a browser tab or the home-screen app) check for a new version when you switch back to them and every few minutes, then reload themselves, but never while you're typing or editing. Publish changes with `./publish.sh "what changed"`, which stamps a new version into `index.html` and `version.txt` and pushes.
- **Live updates** use Supabase Realtime. If changes only show up after about 30 seconds instead of instantly, open **Realtime → Settings** in Supabase and make sure public channel access is allowed. The app also refreshes whenever you switch back to it.
