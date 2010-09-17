package TradeSpring::Broker::Role::LIT;
use Moose::Role;
use Method::Signatures::Simple;
use Hash::Util::FieldHash qw(id);

requires 'on_price';

has lit_orders => (is => "rw", isa => "HashRef", default => sub { {} });

around 'submit_order' => sub {
    my $next = shift;
    my ($self, $order, %args) = @_;
    if ($order->{type} eq 'lit') {
        my $o =
        { order => $order,
          matched => 0,
          execute => sub { $_[0] * $order->{dir} <= $order->{price} * $order->{dir} },
          %args };

        return $self->lit_orders->{$order->{id}} = $o;
    }
    return $next->(@_);
};

around 'cancel_order' => sub {
    my $next = shift;
    my ($self, $id, $cb) = @_;
    if (my $o = delete $self->lit_orders->{$id}) {
        $o->{cancelled}++;
        $self->cancel_order($o->{_current_order}{order}{id}, sub {})
            if $o->{_current_order};
        return $o->{on_summary}->($o->{matched}, $o->{order}{qty} - $o->{matched});
    }
    $next->(@_);
};

before 'on_price' => method ($price, $qty_limit, $time) {
    for (keys %{$self->lit_orders}) {
        my $o = $self->lit_orders->{$_};
        next if !$o || $o->{_current_order} || $o->{cancelled};
        unless ($o->{submitted}) {
            ++$o->{submitted};
            $o->{on_ready}->('new') if $o->{on_ready};
        }
        if ($o->{execute}->($price)) {
#            warn "==> submitting lmt / $o->{order}{qty} / $o $o->{on_summary}";

            my $new_o = {
                dir => $o->{order}{dir},
                qty => $o->{order}{qty} - $o->{matched},
                type => 'lmt',
                tif => $o->{order}{tif},
                price => $o->{order}{price},
            };
            my $id = $new_o->{id} = 't'.id($new_o);

            $o->{_current_order} =
                $self->submit_order
                    ($new_o,
                     on_ready => $o->{on_error},
                     on_ready => $o->{on_ready},
                     on_match => sub {
                         $o->{on_match}->(@_);
                     },
                     on_summary => sub {
                         my ($matched, $cancelled) = @_;
                         # XXX: fill_order, but we want to call vanilla one;
#                         $self->TradeSpring::Broker::fill_order($o, $o->{_current_order}{price_sum} * $matched, $matched, $o->{_current_order}{last_fill_time});
                         $o->{matched} += $matched;
                         $o->{price_sum} ||= 0;
                         $o->{price_sum} += $o->{_current_order}{price_sum} * $matched;
                         $o->{last_fill_time} = $o->{_current_order}{last_fill_time};
                         if ($o->{matched} == $o->{order}{qty}) {
                             $o->{on_summary}->($o->{matched}, 0);
                             delete $self->lit_orders->{$o->{order}{id}}
                         }
                         delete $o->{_current_order};

                     });
        }
    }
};

__PACKAGE__
