-- Migration 045: Clean raw thinking traces (<think>...</think> or ...</think>) from assistant messages
-- Moves any thinking content before </think> into meta->'thinking' and strips it from content.

UPDATE messages
SET
  meta = jsonb_set(
    COALESCE(meta, '{}'::jsonb),
    '{thinking}',
    to_jsonb(
      TRIM(
        COALESCE(meta->>'thinking' || E'\n\n', '') ||
        REGEXP_REPLACE(SPLIT_PART(content, '</think>', 1), '^<think>', '')
      )
    )
  ),
  content = TRIM(SPLIT_PART(content, '</think>', 2))
WHERE role = 'assistant' AND content LIKE '%</think>%';
