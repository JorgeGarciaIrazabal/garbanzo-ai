-- User preferences persisted on the User row.
-- default_model holds the user's preferred default LLM model id, used when
-- creating new conversations. NULL means "fall back to server default".

ALTER TABLE users ADD COLUMN IF NOT EXISTS default_model VARCHAR(100);

-- Allow email changes by cascading updates of users.email to every FK that
-- references it. Constraint names are auto-generated, so we look them up
-- from information_schema and rebuild each with ON UPDATE CASCADE while
-- preserving the existing ON DELETE behavior.
DO $$
DECLARE
    r record;
    on_delete text;
BEGIN
    FOR r IN
        SELECT
            tc.table_schema,
            tc.table_name,
            tc.constraint_name,
            kcu.column_name,
            rc.delete_rule,
            rc.update_rule
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
         AND tc.table_schema = kcu.table_schema
        JOIN information_schema.referential_constraints rc
          ON rc.constraint_name = tc.constraint_name
         AND rc.constraint_schema = tc.table_schema
        JOIN information_schema.constraint_column_usage ccu
          ON rc.unique_constraint_name = ccu.constraint_name
         AND rc.unique_constraint_schema = ccu.constraint_schema
        WHERE tc.constraint_type = 'FOREIGN KEY'
          AND ccu.table_name = 'users'
          AND ccu.column_name = 'email'
    LOOP
        IF r.update_rule = 'CASCADE' THEN
            CONTINUE;
        END IF;

        on_delete := CASE r.delete_rule
            WHEN 'CASCADE' THEN 'CASCADE'
            WHEN 'SET NULL' THEN 'SET NULL'
            WHEN 'SET DEFAULT' THEN 'SET DEFAULT'
            WHEN 'RESTRICT' THEN 'RESTRICT'
            ELSE 'NO ACTION'
        END;

        EXECUTE format(
            'ALTER TABLE %I.%I DROP CONSTRAINT %I',
            r.table_schema, r.table_name, r.constraint_name
        );
        EXECUTE format(
            'ALTER TABLE %I.%I ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES users(email) ON UPDATE CASCADE ON DELETE %s',
            r.table_schema, r.table_name, r.constraint_name, r.column_name, on_delete
        );
    END LOOP;
END $$;
