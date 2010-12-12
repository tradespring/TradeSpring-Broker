package TradeSpring::Broker::Local;
use Moose;
use Hash::Util::FieldHash qw(id);
use Method::Signatures::Simple;
use List::Util qw(min);
use AnyEvent;

extends 'TradeSpring::Broker';

has '+_trait_namespace' => (default => 'TradeSpring::Broker::Role');

has local_orders => (is => "rw", isa => "HashRef", default => sub { {} });
has hit_probability => (is => "rw", isa => "Int", default => sub { 1 });

has timestamp => (is => "rw", isa => "Num");

method submit_order ($order, %args) {
    my $type = $order->{type};
    die unless $type eq 'mkt' || $type eq 'lmt';

    my $o =
    { order => $order,
      matched => 0,
      execute =>
          ( $type eq 'mkt' ? sub { $_[0] }
          : $type eq 'lmt' ? sub { $_[0] * $order->{dir} <= $order->{price} * $order->{dir} ? $order->{price} : undef }
          : die "unknown order type: $type" ),
      %args };

    my $id = $order->{id};

    $o->{on_ready_timer} = AnyEvent->timer( after => 0.5,
                                            cb => sub {
                                                delete $o->{on_ready_cv};
                                                return if $o->{submitted} || $o->{cancelled};
                                                unless ($o->{submitted}) {
                                                    ++$o->{submitted};
                                                    $o->{on_ready}->('new')
                                                }
                                            })
        if $o->{on_ready};
    $self->{timestamp} = AnyEvent->now;
    return $self->local_orders->{$id} = $o;
}


method cancel_order ($id, $cb) {
    my $o = delete $self->local_orders->{$id} or return warn "order $id not found";
    $cb->('cancelled');
    $o->{cancelled}++;
    $o->{on_summary}->($o->{matched}, $o->{order}{qty} - $o->{matched});
    delete $o->{execute};
    delete $o->{on_ready_timer};
    return 1;
}

use List::MoreUtils qw(part);

method on_price ($price, $qty_limit, $time) {
    for (keys %{$self->local_orders}) {
        my $o = $self->local_orders->{$_};
        next if !$o || $o->{cancelled};
        my $just_submitted;

        unless ($o->{seen_order}) {
            $just_submitted = 1;
            ++$o->{seen_order};
        }

        unless ($o->{submitted}) {
            ++$o->{submitted};
            delete $o->{on_ready_timer};
            $o->{on_ready}->('new') if $o->{on_ready};
        }
        if (my $p = $o->{execute}->($price)) {
            if ($o->{order}{type} eq 'lmt' && $o->{order}{price} == $price) {
                if (int(rand(100)) >= $self->hit_probability*100) {
                    return;
                }
            }

            if ($just_submitted) {
                $p = $price;
            }
            my $qty = min($qty_limit ? $qty_limit : (), $o->{order}{qty} - $o->{matched});

            $self->fill_order($o, $p, $qty, $time);
        }
        if ($o->{order}{qty} != $o->{matched} &&
            $o->{order}{tif} && $o->{order}{tif} eq 'IOC') {
            $self->cancel_order($_, sub {});
        }
    }
}

after 'fill_order' => method ($o) {
    if ($o->{matched} == $o->{order}{qty}) {
        delete $o->{execute};
        delete $self->local_orders->{$o->{order}{id}};
    }
};

__PACKAGE__->meta->make_immutable;
no Moose;
1;
