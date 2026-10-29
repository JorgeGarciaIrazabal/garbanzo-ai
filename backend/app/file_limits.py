"""File transfer budget shared by folder storage, workflows and document readers.

Keep this module import-free: isolated document workers must not load API,
database or provider configuration just to read their input budget.
"""

MAX_FILE_BYTES = 25 * 1024 * 1024
