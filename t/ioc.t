#!/usr/bin/perl -w
use strict;
use Test::More;
use TradeSpring::Broker::Local;

my $broker = TradeSpring::Broker::Local->new_with_traits
     (traits => ['Stop']);

my $order = {};


sub mk_cb {
    my $log = shift;
    my $ready = shift;
    my @cb = qw(match summary cancel);
    push @cb, 'ready' if $ready;
    map { my $name = $_;
          ("on_$name" => sub { push @$log, [$name, @_] }) } @cb;
}

{
    my $log = [];
    my $order_id = $broker->register_order( { dir => 1,
                                              type => 'lmt',
                                              tif => 'IOC',
                                              price => 7000,
                                              qty => 1 },
                                            mk_cb($log, 1));
    diag $order_id;
    $broker->on_price(7010);
    is_deeply($log, [['ready', $order_id, 'new'],
                     ['summary', 0, 1]]);

}

{
    my $log = [];
    my $order_id = $broker->register_order( { dir => 1,
                                              type => 'lmt',
                                              tif => 'IOC',
                                              price => 7000,
                                              qty => 5 },
                                            mk_cb($log, 1));
    diag $order_id;
    $broker->on_price(7000, 3);
    $broker->on_price(7000, 10);
    is_deeply($log, [['ready', $order_id, 'new'],
                     ['match', 7000, 3],
                     ['summary', 3, 2]]);

}

done_testing;
