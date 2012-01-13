use inc::Module::Install;
  
name           'LucyX-Simple';
all_from       'lib/LucyX/Simple.pm';

requires 'Moose';
requires 'Moose::Util::TypeConstraints';
requires 'namespace::autoclean';
requires 'Lucy';
requires 'Data::Page';
requires 'Exception::Simple';

test_requires 'Test::More';
test_requires 'Test::Exception';
test_requires 'Lucy::Store::RAMFolder';

auto_install;
WriteAll;
