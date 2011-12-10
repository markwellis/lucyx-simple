use inc::Module::Install;
  
  # Define metadata
name           'LucyX-Simple';
all_from       'lib/LucyX/Simple.pm';
  
# Specific dependencies
requires       'Data::Page';
requires       'Lucy';
test_requires 'Test::More';

auto_install;
WriteAll;
