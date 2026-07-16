import sqlite3
conn = sqlite3.connect('dostavka.db')
tables = conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()
print('tables:', tables)
for t in tables:
    cnt = conn.execute(f'SELECT COUNT(*) FROM {t[0]}').fetchone()[0]
    print(f'  {t[0]}: {cnt} rows')
conn.close()
