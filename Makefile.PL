sub readme_from {}; sub auto_include_deps {}; sub author_tests {}; sub auto_set_repository {};
use inc::Module::Install;
name 'TradeSpring-Broker';
all_from 'lib/TradeSpring/Broker.pm';
build_requires 'Test::More';
requires 'Method::Signatures::Simple';
requires 'Moose';
requires 'Log::Log4perl';
requires 'MooseX::ClassAttribute';
requires 'MooseX::Traits';
requires 'MooseX::Log::Log4perl';
requires 'AnyEvent';

test_requires 'Test::LeakTrace';
test_requires 'Test::Deep';

auto_include_deps;
author_tests('xt');
WriteAll;
