#!/usr/bin/perl -w
use strict;
use Test::More;
use TradeSpring::Broker::Local;

my $broker = TradeSpring::Broker::Local->new_with_traits
     (traits => ['LIT']);

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
                                              type => 'lit',
                                              tif => 'IOC',
                                              price => 7000,
                                              qty => 10 },
                                            mk_cb($log, 1));
    diag $order_id;
    $broker->on_price(7010);
    is_deeply($log, [['ready', $order_id, 'new']]);

    @$log = ();

    $broker->on_price(7000, 1);
    $broker->on_price(7000, 1);

    is_deeply($log, [['ready', $order_id, 'new'],
                     ['match', 7000, 1],
                     ['ready', $order_id, 'new'],
                     ['match', 7000, 1],
                 ]);

    is ($broker->get_order($order_id)->{matched}, 2);

    is(scalar keys %{$broker->local_orders}, 0);
    is(scalar keys %{$broker->orders}, 1);

    @$log = ();
    $broker->on_price(6999, 1);
    $broker->on_price(6998, 9);
    is_deeply($log, [['ready', $order_id, 'new'],
                     ['match', 7000, 1],
                     ['ready', $order_id, 'new'],
                     ['match', 7000, 7],
                     ['summary', 10, 0]]);

    is(scalar keys %{$broker->local_orders}, 0);
    is(scalar keys %{$broker->lit_orders}, 0);
    is(scalar keys %{$broker->orders}, 0);
}

{
    my $log = [];
    my $order_id = $broker->register_order( { dir => 1,
                                              type => 'lit',
                                              tif => 'IOC',
                                              price => 7000,
                                              qty => 10 },
                                            mk_cb($log, 1));
    diag $order_id;
    $broker->on_price(7010);
    is_deeply($log, [['ready', $order_id, 'new']]);

    @$log = ();

    $broker->on_price(7000, 1);
    $broker->on_price(7000, 1);

    is_deeply($log, [['ready', $order_id, 'new'],
                     ['match', 7000, 1],
                     ['ready', $order_id, 'new'],
                     ['match', 7000, 1],
                 ]);

    is(scalar keys %{$broker->local_orders}, 0);
    is(scalar keys %{$broker->orders}, 1);

    @$log = ();
    $broker->cancel_order($order_id, sub { 'cancelled'});

    is_deeply($log, [['summary', 2, 8]]);

    is(scalar keys %{$broker->local_orders}, 0);
    is(scalar keys %{$broker->orders}, 0);
}

{
    my $log = [];
    my $order_id = $broker->register_order( { dir => 1,
                                              type => 'lit',
                                              tif => 'ROD',
                                              price => 7000,
                                              qty => 10 },
                                            mk_cb($log, 1));
    diag $order_id;
    $broker->on_price(7010);
    is_deeply($log, [['ready', $order_id, 'new']]);

    @$log = ();

    $broker->on_price(7000, 1);
    $broker->on_price(7000, 1);

    is_deeply($log, [['ready', $order_id, 'new'],
                     ['match', 7000, 1],
                     ['match', 7000, 1],
                 ]);

    is(scalar keys %{$broker->local_orders}, 1);
    is(scalar keys %{$broker->lit_orders}, 1);
    is(scalar keys %{$broker->orders}, 1);

    @$log = ();
    $broker->cancel_order($order_id, sub { 'cancelled'});

    is_deeply($log, [['summary', 2, 8]]);

    is(scalar keys %{$broker->local_orders}, 0);
    is(scalar keys %{$broker->lit_orders}, 0);
    is(scalar keys %{$broker->orders}, 0);
}


done_testing;
