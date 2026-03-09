## Summary

Fix datetime handling bugs that cause crashes in MeshChat's web API when Peewee ORM returns `datetime` objects instead of strings.

**Fixes:** #144, #146, #139

## Bugs Fixed

### 1. `fromisoformat()` crashes on datetime objects (lines 1530, 1535)
`datetime.fromisoformat(latest_announce.updated_at)` fails with `TypeError` because Peewee's `DateTimeField` returns a `datetime` object, not a string. Affects the `/api/v1/destination/{hash}/signal-metrics` endpoint.

### 2. `strptime()` crashes on datetime objects (lines 3281-3282)
`datetime.strptime(lxmf_conversation_read_state.last_read_at, fmt)` fails for the same reason. Affects `is_lxmf_conversation_unread()`, breaking conversation read state tracking.

### 3. JSON serialization fails for datetime objects
`convert_db_announce_to_dict()`, `convert_db_favourite_to_dict()`, and `convert_db_lxmf_message_to_dict()` pass raw `datetime` objects into `web.json_response()` → `json.dumps()` raises `TypeError: Object of type datetime is not JSON serializable`.

### 4. Interface stats `network_id` bytes not converted to hex
`get_interface_stats` converts some bytes fields to hex but misses `network_id`, causing the same JSON serialization crash.

## Approach

- Added `_ensure_datetime(value)` helper: accepts both `datetime` objects and strings, normalizing to `datetime`
- Added `_datetime_to_str(value)` helper: converts `datetime` to ISO 8601 string for JSON serialization
- Applied `_ensure_datetime()` at all 4 parsing sites (replaces `fromisoformat`/`strptime`)
- Applied `_datetime_to_str()` at all 8 dict serialization sites (`created_at`/`updated_at` fields)
- Fixed `parent_interface_hash` guard to check the key directly instead of `parent_interface_name`
- Added `network_id` bytes→hex conversion

## Test Plan

- [x] `python3 -c "import ast; ast.parse(open('meshchat.py').read())"` — syntax valid
- [x] No remaining `strptime`/`fromisoformat` calls on DB DateTimeField values
- [x] All `created_at`/`updated_at` in API response dicts use `_datetime_to_str()`
- [ ] Manual testing with running MeshChat instance
