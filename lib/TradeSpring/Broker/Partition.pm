package TradeSpring::Broker::Partition;
use 5.10.1;
use AnyEvent;
use Moose;
use Hash::Util::FieldHash qw(id);
use Method::Signatures::Simple;
use List::Util qw(min);

extends 'TradeSpring::Broker';

with 'MooseX::Traits';
with 'MooseX::Log::Log4perl';

has local_orders => (is => "rw", isa => "HashRef", default => sub { {} });

has '+_trait_namespace' => (default => 'TradeSpring::Broker::Role');

has backends => (is => 'ro', isa => 'ArrayRef', default => sub { [] });

method on_price {
    for (@{$self->backends}) {
        $_->{broker}->on_price(@_);
    }
}

method submit_order ($order, %args) {
    my $type = $order->{type};
    die unless $type eq 'mkt' || $type eq 'lmt';

    my $o =
    { order => $order,
      matched => 0,
      %args };
    my $id = $order->{id};

    my $qty = $order->{qty};
    my $ready_cv = AE::cv;
    my $new_ready = AE::cv;
    my $ready_type;
    $ready_cv->cb(
        sub {
            $o->{on_ready}->($ready_type);
            $ready_cv = $new_ready;
            undef $ready_type;
            $new_ready = AE::cv;
            $new_ready->cb($ready_cv->cb);
        } );
    $new_ready->cb($ready_cv->cb);
    my $summary_cv = AE::cv;
    $summary_cv->cb(sub {
                        my $unfilled = $o->{order}{qty} - $o->{matched};
                        $o->{on_summary}->($o->{matched}, $unfilled)
                            if $unfilled;
                    } );
    for my $b (@{$self->backends}) {
        if ($qty >= $b->{qtymap}) {
            my $thisqty = int($qty / $b->{qtymap});
            $qty -= $thisqty * $b->{qtymap};
            my $thiso = {
                %$order,
                qty => $thisqty,
            };
            delete $thiso->{id};
            $ready_cv->begin;
            $summary_cv->begin;
            my $thisid; $thisid = $b->{broker}->register_order(
                $thiso,
                on_error => sub {
                    $self->log->error(join(',', @_));
                },
                on_ready => sub {
                    my ($id,$type) = @_;
                    unless ($ready_type) {
                        $ready_type = $type
                    }
                    elsif ($ready_type ne $type) {
                        $self->log->error("inconsistent $ready_type vs $type");
                    }
                    $new_ready->begin;
                    $ready_cv->end;
                },
                on_match => sub {
                    my ($price, $qty) = @_;
                    $qty *= $b->{qtymap};
                    $self->fill_order($o, $price, $qty, { timestamp => AnyEvent->now});
                },
                on_summary => sub {
                    $summary_cv->end;
                }
            );
            push @{$o->{_orders} ||= []}, [$b, $thisid];
        }
    }

    return $self->local_orders->{$id} = $o;
}


method cancel_order ($id, $cb) {
    my $o = delete $self->local_orders->{$id} or return warn "order $id not found";
    my $cancelled = AE::cv;
    $cancelled->cb(sub {
                       $cb->('cancelled');
                   });
    for (@{$o->{_orders}}) {
        my ($b, $thisid) = @$_;
        $cancelled->begin;
        $b->{broker}->cancel_order($thisid, sub {
                                       $cancelled->end;
                                   });
    }
    return 1;

}

after 'fill_order' => method ($o) {
    if ($o->{matched} == $o->{order}{qty}) {
        delete $self->local_orders->{$o->{order}{id}};
    }
};


__PACKAGE__->meta->make_immutable;
no Moose;
1;


