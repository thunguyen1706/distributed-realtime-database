CREATE TABLE shards (
    shard_id INT PRIMARY KEY,
    host TEXT NOT NULL,
    port INT NOT NULL,
    db_name TEXT NOT NULL,
    username TEXT NOT NULL,
    password TEXT NOT NULL
);

INSERT INTO shards (shard_id, host, port, db_name, username, password) VALUES
(0, 'pg_shard_0', 5432, 'posts', 'postgres', '${PG_SHARD_PASS}'),
(1, 'pg_shard_1', 5432, 'posts', 'postgres', '${PG_SHARD_PASS}'),
(2, 'pg_shard_2', 5432, 'posts', 'postgres', '${PG_SHARD_PASS}');
