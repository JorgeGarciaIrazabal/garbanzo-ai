"""Business logic and integrations; import classes from their owning modules.

Keep this namespace free of service imports so isolated workers and simple
helpers do not initialize database, conversation or provider dependencies.
"""
