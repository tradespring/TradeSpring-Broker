use inc::Module::Install;
name 'TradeSpring-Broker';
all_from 'lib/TradeSpring/Broker.pm';
build_requires 'Test::More';
auto_include_deps;
author_tests('xt');
WriteAll;
