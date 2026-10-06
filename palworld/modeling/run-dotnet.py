from pathlib import Path
import os,sys,subprocess
root=Path(__file__).resolve().parent
env=os.environ.copy();env.update(DOTNET_CLI_HOME=str(root/'dotnet-home'),NUGET_PACKAGES=str(root/'nuget-packages'),DOTNET_SKIP_FIRST_TIME_EXPERIENCE='1',DOTNET_CLI_TELEMETRY_OPTOUT='1',HTTPS_PROXY='http://127.0.0.1:7897',HTTP_PROXY='http://127.0.0.1:7897',NO_PROXY='127.0.0.1,localhost')
raise SystemExit(subprocess.run([str(root/'dotnet/dotnet'),*sys.argv[1:]],env=env).returncode)
