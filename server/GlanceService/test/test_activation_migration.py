"""Exercise real SQLite billing triggers without starting workerd or touching D1."""
from pathlib import Path
import sqlite3
import unittest


class ActivationMigrationTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:")
        self.db.execute("PRAGMA foreign_keys=ON")
        for path in sorted((Path(__file__).resolve().parents[1] / "migrations").glob("*.sql")):
            self.db.executescript(path.read_text())
        self.db.execute("INSERT INTO users(id,email,auth_provider,created_at,updated_at) VALUES(1,'fixture@example.com','email','2026-11-01','2026-11-01')")
        self.db.execute("INSERT INTO user_credit_ledger(id,user_id,amount,reason,actor_id,created_at) VALUES('signup:1',1,100,'signup_bonus','test','2026-11-01')")

    def tearDown(self):
        self.db.close()

    def task(self, name, mode):
        self.db.execute("""INSERT INTO widget_tasks(id,widget_id,version_id,command_id,owner_id,type,
            input_json,parameters_json,status,created_at,credit_cost,billing_mode)
            VALUES(?,'widget','version','run','user_1','production','{}','{}','queued','2026-11-02',100,?)""", (name, mode))

    def test_depletion_and_refund_preserve_environment_and_balance(self):
        for name, mode in [("unknown", None), ("sandbox", "test"), ("release", "prod")]:
            self.task(name, mode)
            self.assertEqual(self.db.execute("SELECT credits FROM users WHERE id=1").fetchone()[0], 0)
            self.db.execute("UPDATE widget_tasks SET status='failed' WHERE id=?", (name,))
            self.db.execute("UPDATE widget_tasks SET status='failed' WHERE id=?", (name,))
            self.assertEqual(self.db.execute("SELECT credits FROM users WHERE id=1").fetchone()[0], 100)
        rows = self.db.execute("SELECT billing_mode,COUNT(*) FROM billing_events WHERE kind='gift_depleted' GROUP BY billing_mode").fetchall()
        self.assertEqual(rows, [(None, 1), ("prod", 1), ("test", 1)])
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM user_credit_ledger WHERE id LIKE 'refund:%'").fetchone()[0], 3)
        self.assertEqual(self.db.execute("PRAGMA foreign_key_check").fetchall(), [])

    def test_first_preview_deduplicates_accounts_but_not_environments(self):
        for name, mode in [("anonymous", "test"), ("signed-in", "test"), ("release", "prod")]:
            self.db.execute("""INSERT OR IGNORE INTO billing_events(id,kind,device_hash,created_at,billing_mode,media_kind)
                VALUES(?,'first_preview_success','device','2026-11-02',?,'image')""", (name, mode))
        self.assertEqual(self.db.execute("SELECT billing_mode,COUNT(*) FROM billing_events GROUP BY billing_mode").fetchall(), [("prod", 1), ("test", 1)])


if __name__ == "__main__":
    unittest.main()
