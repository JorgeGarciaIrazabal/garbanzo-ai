"""Service namespaces and parser workers do not initialize unrelated services."""

import subprocess
import sys


def test_service_namespace_import_loads_no_service_modules():
    proc = subprocess.run(  # noqa: S603
        [
            sys.executable,
            "-c",
            "import sys; import app.services; "
            "assert not [name for name in sys.modules if name.startswith('app.services.')]; "
            "assert 'app.db.session' not in sys.modules",
        ],
        capture_output=True,
        text=True,
        timeout=20,
        check=False,
    )
    assert proc.returncode == 0, proc.stderr
