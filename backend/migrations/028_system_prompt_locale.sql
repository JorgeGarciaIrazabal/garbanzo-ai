-- Adds a locale column to system_prompt_templates so built-in templates can be
-- seeded in multiple languages (e.g. English + Spanish) without duplicating
-- them in the picker. User-saved templates keep locale NULL (they are
-- language-neutral — the user typed them). NULL also acts as a wildcard so
-- existing rows continue to surface for any requested locale.
--
-- Existing builtin rows are tagged 'en' so the Spanish seed (028's companion
-- data change in SystemPromptService) only inserts the missing 'es' rows.
ALTER TABLE system_prompt_templates
    ADD COLUMN IF NOT EXISTS locale VARCHAR(5) DEFAULT NULL;

UPDATE system_prompt_templates
    SET locale = 'en'
    WHERE is_builtin = TRUE AND locale IS NULL;