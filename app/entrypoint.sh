#!/bin/sh
# minimal prod entrypoint: nothing to execute, just the app.
exec python3 -c "import runpy; runpy.run_path('/app/app.py', run_name='__main__')"