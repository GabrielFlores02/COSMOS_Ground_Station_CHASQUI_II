WELCOME to COSMOS!

To get started with a demonstration installation of COSMOS, run the
LAUNCH_DEMO.bat file. This will always launch the configuration stored
in the Demo directory.

The Vendor directory contains the full COSMOS installation.
This includes Ruby, the Ruby development kit used to compile Ruby extentions,
and all the gems (Ruby libraries) needed to start using COSMOS.

To get started with your own custom COSMOS installation, type
'cosmos install <DIRECTORY>' to create a simple COSMOS configuration
in the named directory. If you have the COSMOS_DIR
environment variable set (it was an option during the installer) you can
place this directory anywhere you want. When you run any of the tools using
the provided Windows Batch scripts they will automatically reference this
environment variable to locate the COSMOS installation.

If you did not set the COSMOS_DIR environment variable you must place
new COSMOS installations here next to the Demo and Vendor directories.
NOTE: You can manually set this environment variable at any time.

You SHOULD version control your new COSMOS configuration directory
going forward. All of the COSMOS configuration files are text based
to provide easy to see change history.

For more information please see:
http://cosmosrb.com

