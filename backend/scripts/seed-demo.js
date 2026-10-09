/*
 * seed-demo.js — Load a small demo dataset so you can try SplitEase right away.
 *
 * Usage:
 *   npm run seed:demo            — only runs on an empty database (no accounts yet)
 *   npm run seed:demo -- --force — REPLACES all data with the demo dataset
 *
 * Sign in afterwards with:  demo@splitease.app  /  splitease-demo
 * (The other demo people use the same password: aisyah@, weijie@, priya@, daniel@ splitease.app.)
 */
require("dotenv").config();
const crypto = require("crypto");
const supabase = require("../src/config/supabase");
const { readDb, writeDb } = require("../src/services/supabaseService");

const DEMO_PASSWORD = "splitease-demo";
const force = process.argv.includes("--force");

const daysAgo = (n) => new Date(Date.now() - n * 864e5).toISOString().split("T")[0];
const hash = (password, salt) => crypto.scryptSync(password, salt, 64).toString("hex");

const people = [
  { id: "demo-alex", name: "Alex Tan", avatar: "🧑🏻‍💻", email: "demo@splitease.app" },
  { id: "demo-aisyah", name: "Aisyah", avatar: "🧕🏽", email: "aisyah@splitease.app" },
  { id: "demo-weijie", name: "Wei Jie", avatar: "🧑🏻", email: "weijie@splitease.app" },
  { id: "demo-priya", name: "Priya", avatar: "👩🏾", email: "priya@splitease.app" },
  { id: "demo-daniel", name: "Daniel", avatar: "🧔🏻", email: "daniel@splitease.app" },
].map((u) => ({ ...u, currency: "MYR" }));
const [alex, aisyah, weijie, priya] = people;
const ids = (...us) => us.map((u) => u.id);

const groups = [
  {
    id: "demo-penang",
    name: "Penang Trip",
    emoji: "🏖️",
    description: "Three days of char kway teow, street art and beaches",
    createdAt: daysAgo(12),
    members: [alex, aisyah, weijie, priya],
    expenses: [
      { id: "demo-e1", description: "Hotel, 2 nights", amount: 640, paidBy: alex.id, category: "accommodation", date: daysAgo(11), splitBetween: ids(alex, aisyah, weijie, priya) },
      { id: "demo-e2", description: "Seafood dinner at Gurney", amount: 248, paidBy: aisyah.id, category: "food", date: daysAgo(10), splitBetween: ids(alex, aisyah, weijie, priya) },
      { id: "demo-e3", description: "Grab rides", amount: 86.4, paidBy: weijie.id, category: "transport", date: daysAgo(10), splitBetween: ids(alex, aisyah, weijie, priya),
        splitAmounts: { [alex.id]: 30, [aisyah.id]: 20, [weijie.id]: 18.4, [priya.id]: 18 } },
      { id: "demo-e4", description: "Durian at Balik Pulau", amount: 66, paidBy: priya.id, category: "food", date: daysAgo(9), splitBetween: ids(alex, weijie, priya) },
      { id: "demo-e5", description: "Escape Theme Park tickets", amount: 296, paidBy: alex.id, category: "entertainment", date: daysAgo(9), splitBetween: ids(alex, aisyah, weijie, priya) },
      // A settle-up is stored as a special expense: Priya paid Alex back RM100.
      { id: "demo-s1", description: "Settlement", amount: 100, paidBy: priya.id, category: "settlement", date: daysAgo(6), splitBetween: ids(alex) },
    ],
    settlements: [],
  },
  {
    id: "demo-house",
    name: "SS15 Housemates",
    emoji: "🏠",
    description: "Rent, bills and groceries",
    createdAt: daysAgo(40),
    members: [alex, weijie, priya],
    expenses: [
      { id: "demo-e6", description: "TNB electricity bill", amount: 183.6, paidBy: weijie.id, category: "utilities", date: daysAgo(8), splitBetween: ids(alex, weijie, priya) },
      { id: "demo-e7", description: "Unifi Wi-Fi", amount: 129, paidBy: alex.id, category: "utilities", date: daysAgo(5), splitBetween: ids(alex, weijie, priya) },
      { id: "demo-e8", description: "Lotus's groceries", amount: 96.5, paidBy: priya.id, category: "shopping", date: daysAgo(0), splitBetween: ids(alex, weijie, priya) },
    ],
    settlements: [],
  },
];

// Every expense records its group id and currency.
for (const g of groups) for (const e of g.expenses) Object.assign(e, { groupId: g.id, currency: "MYR" });

(async () => {
  const existing = await readDb();
  if ((existing.accounts || []).length > 0 && !force) {
    console.error("Database already has accounts. Re-run with --force to replace everything with demo data.");
    process.exit(1);
  }

  const accounts = people.map((u) => {
    const salt = crypto.randomBytes(16).toString("hex");
    return { userId: u.id, email: u.email, passwordHash: hash(DEMO_PASSWORD, salt), salt, createdAt: daysAgo(45) };
  });
  await writeDb({ currentUserId: alex.id, users: people, accounts, groups });

  // Friendships live outside the full-database sync.
  const demoIds = people.map((u) => u.id);
  await supabase.from("friendships").delete().in("requester_id", demoIds);
  const { error } = await supabase.from("friendships").insert([
    { requester_id: alex.id, target_id: aisyah.id, status: "accepted" },
    { requester_id: weijie.id, target_id: alex.id, status: "accepted" },
    { requester_id: alex.id, target_id: priya.id, status: "accepted" },
    { requester_id: "demo-daniel", target_id: alex.id, status: "pending" },
  ]);
  if (error) throw new Error(`Friendship seed failed: ${error.message}`);

  console.log("Demo data loaded. Sign in with demo@splitease.app / " + DEMO_PASSWORD);
})().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
