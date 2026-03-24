-- Tags: no-parallel
-- Test SYSTEM RELOAD DICTIONARY ... INVALIDATED
-- Verifies that INVALIDATED uses incremental reload (via update_field / clone),
-- as opposed to full reload which rebuilds from scratch.
-- Observable difference: deleted rows in the source persist after incremental reload
-- but disappear after full reload.

DROP DICTIONARY IF EXISTS test_dict_invalidated;
DROP TABLE IF EXISTS test_dict_source;

CREATE TABLE test_dict_source
(
    id UInt64,
    value String,
    updated_at DateTime DEFAULT now()
)
ENGINE = MergeTree()
ORDER BY id;

INSERT INTO test_dict_source (id, value) VALUES (1, 'one'), (2, 'two');

CREATE DICTIONARY test_dict_invalidated
(
    id UInt64,
    value String,
    updated_at DateTime
)
PRIMARY KEY id
SOURCE(CLICKHOUSE(TABLE 'test_dict_source' update_field 'updated_at' update_lag 0))
LAYOUT(HASHED())
LIFETIME(MIN 0 MAX 0);

-- Initial load: both rows present
SELECT dictGet('test_dict_invalidated', 'value', toUInt64(1));
SELECT dictGet('test_dict_invalidated', 'value', toUInt64(2));

-- Delete row 2 from source, update row 1
SELECT sleep(1) FORMAT Null; -- ensure updated_at is strictly newer
TRUNCATE TABLE test_dict_source;
INSERT INTO test_dict_source (id, value) VALUES (1, 'one_updated');

-- Incremental reload: row 2 should still be in the dictionary (from previous load),
-- because update_field only fetches rows newer than last load time.
SYSTEM RELOAD DICTIONARY test_dict_invalidated INVALIDATED;
SELECT dictGet('test_dict_invalidated', 'value', toUInt64(1));
SELECT dictGet('test_dict_invalidated', 'value', toUInt64(2));

-- Full reload: row 2 should be gone (rebuilt from scratch).
SYSTEM RELOAD DICTIONARY test_dict_invalidated;
SELECT dictGet('test_dict_invalidated', 'value', toUInt64(1));
SELECT dictGet('test_dict_invalidated', 'value', toUInt64(2));

-- Verify formatting round-trip
EXPLAIN SYNTAX SYSTEM RELOAD DICTIONARY test_dict_invalidated INVALIDATED;

DROP DICTIONARY test_dict_invalidated;
DROP TABLE test_dict_source;
