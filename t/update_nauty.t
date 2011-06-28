#!/usr/bin/perl -w
use strict;
use Test::More;
use lib 't/lib';
use TradeSpring::Broker::Local;

my $broker = TradeSpring::Broker::Local->new_with_traits
     (traits => ['Stop', 'Update', '+Naughty'],
      extra_price_on_cancel => 1);

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
    my $order_id = $broker->register_order( 1, 'lmt', 7000, 2,
                                          mk_cb($log, 1));
    diag $order_id;
    $broker->on_price(7010);
    is_deeply($log, [['ready', $order_id, 'new']]);
    $broker->on_price(7000, 1);
    is_deeply($log, [['ready', $order_id, 'new'],
                     ['match', 7000, 1]]);

    @$log = ();
    $broker->update_order( $order_id, 6999, undef, sub {
                               push @$log, ['updating'];
                           });

    is_deeply($log, [
                     ['match', 7000, 1],
                     ['summary', 2, 0]]);

    is(scalar keys %{$broker->local_orders}, 0);
}


{
    my $log = [];
    my $order_id = $broker->register_order( 1, 'lmt', 7000, 3,
                                          mk_cb($log, 1));
    diag $order_id;
    $broker->on_price(7010);
    is_deeply($log, [['ready', $order_id, 'new']]);
    $broker->on_price(7000, 1);
    is_deeply($log, [['ready', $order_id, 'new'],
                     ['match', 7000, 1]]);

    @$log = ();
    $broker->update_order( $order_id, 6999, undef, sub {
                               push @$log, ['updating'];
                           });

    $broker->on_price(7000, 1);

    is_deeply($log, [
                     ['match', 7000, 1],
                     ['updating'],
                     ['ready', $order_id, 'new'],
                 ]);

    my $o = $broker->get_order($order_id);

    @$log = ();
    $broker->on_price(6999, 1);

    is_deeply($log, [
                     ['match', 6999, 1],
                     ['summary', 3, 0]]);

    is(scalar keys %{$broker->local_orders}, 0);
    is($o->{matched}, 3);
    is($o->{price_sum}, 7000 + 7000 + 6999);
}

done_testing;
