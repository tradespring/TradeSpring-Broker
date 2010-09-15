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
    my $order_id = $broker->register_order( 1, 'lmt', 7000, 1,
                                          mk_cb($log, 1));
    diag $order_id;
    $broker->on_price(7010);
    is_deeply($log, [['ready', $order_id, 'new']]);
    $broker->on_price(7001);
    is_deeply($log, [['ready', $order_id, 'new']]);

    $broker->on_price(7000);
    is_deeply($log, [['ready', $order_id, 'new'],
                     ['match', 7000, 1],
                     ['summary', 1, 0]
                 ]);
    is(scalar keys %{$broker->local_orders}, 0);
}

{
    my $log = [];
    my $order_id = $broker->register_order( 1, 'lmt', 7000, 2,
                                            mk_cb($log));

    $broker->on_price(7001);
    is_deeply($log, []);

    $broker->on_price(7000, 1);
    is_deeply($log, [['match', 7000, 1]]);

    $broker->on_price(7001, 1);
    is_deeply($log, [['match', 7000, 1]]);

    $broker->on_price(6999, 1);
    is_deeply($log, [['match', 7000, 1],
                     ['match', 6999, 1],
                     ['summary', 2, 0]]);

    is(scalar keys %{$broker->local_orders}, 0);
}


{
    my $log = [];
    my $order_id = $broker->register_order( 1, 'lmt', 7000, 2,
                                            mk_cb($log));

    $broker->on_price(7001);
    is_deeply($log, []);

    $broker->on_price(7000, 1);
    is_deeply($log, [['match', 7000, 1]]);

    $broker->on_price(7001, 1);
    $broker->cancel_order($order_id,
                          sub { push @$log, ['cancel', @_] } );
    is_deeply($log, [['match', 7000, 1],
                     ['cancel', 'cancelled'],
                     ['summary', 1, 1]]);
    is(scalar keys %{$broker->local_orders}, 0);
    is(scalar keys %{$broker->orders}, 0);
}

{
    my $log = [];
    $broker->hit_probability(0);
    my $order_id = $broker->register_order( 1, 'lmt', 7000, 5,
                                            mk_cb($log));

    $broker->on_price(7001);
    is_deeply($log, []);

    $broker->on_price(7000, 10);
    $broker->on_price(7000, 10);
    is_deeply($log, []);

    $broker->on_price(6999, 1);
    $broker->on_price(7000, 1);
    $broker->on_price(6998, 10);
    # XXX: ensure warning for order not found
    $broker->cancel_order($order_id,
                          sub { push @$log, ['cancel', @_] } );

    is_deeply($log, [['match', 6999, 1],
                     ['match', 6998, 4],
                     ['summary', 5, 0]]);

    is(scalar keys %{$broker->local_orders}, 0);
    is(scalar keys %{$broker->orders}, 0);
}

{
    my $log = [];
    $broker->hit_probability(0);
    my $order_id = $broker->register_order( 1, 'stp', 7000, 5,
                                            mk_cb($log));
    diag $order_id;
    $broker->on_price(6998, 1);
    is_deeply($log, []);

    $broker->on_price(7001, 1);
    $broker->on_price(7000, 10);

    is_deeply($log, [['match', 7001, 1],
                     ['match', 7000, 4],
                     ['summary', 5, 0]]);

    is(scalar keys %{$broker->local_orders}, 0);
    is(scalar keys %{$broker->orders}, 0);
}

done_testing;
