#!/usr/bin/perl -w
use strict;
use Test::More;
use TradeSpring::Broker::Local;

my $broker = TradeSpring::Broker::Local->new_with_traits
     (traits => ['Stop', 'Update']);

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
    my $order_id = $broker->register_order( 1, 'lmt', 7000, 1,
                                          mk_cb($log, 1));
    diag $order_id;
    $broker->on_price(7010);
    is_deeply($log, [['ready', $order_id, 'new']]);
    $broker->on_price(7001);
    is_deeply($log, [['ready', $order_id, 'new']]);

    $broker->update_order( $order_id, 7001, undef, sub {
                               push @$log, ['updating'];
                           });

    $broker->on_price(7001);
    is_deeply($log, [['ready', $order_id, 'new'],
                     ['updating'],
                     ['ready', $order_id, 'new'],
                     ['match', 7001, 1],
                     ['summary', 1, 0]
                 ]);
    is(scalar keys %{$broker->local_orders}, 0);
}

{
    my $log = [];
    my $order_id = $broker->register_order( 1, 'stp', 7000, 1,
                                            mk_cb($log, 1));
    diag $order_id;
    $broker->on_price(6999);
    is_deeply($log, [['ready', $order_id, 'new']]);
    $broker->on_price(6999);
    is_deeply($log, [['ready', $order_id, 'new']]);

    $broker->update_order( $order_id, 6999, undef, sub {
                               push @$log, ['updating'];
                           });

    $broker->on_price(6999);
    is_deeply($log, [['ready', $order_id, 'new'],
                     ['updating'],
                     ['ready', $order_id, 'new'],
                     ['ready', $order_id, 'new'],
                     ['match', 6999, 1],
                     ['summary', 1, 0]
                 ]);
    is(scalar keys %{$broker->local_orders}, 0);
}

done_testing();
