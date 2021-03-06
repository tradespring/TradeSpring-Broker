package TradeSpring::Broker::Role::Update;
use Moose::Role;
use Method::Signatures::Simple;

method update_order($id, $price, $qty, $cb) {
    return;
}

around 'update_order' => sub {
    my ($next, $self, $id, $price, $qty, $cb) = @_;
    return if $self->$next($id, $price, $qty, $cb);
    my $o = $self->get_order($id);

    my $summary = $o->{on_summary};

    $o->{on_summary} = sub {
        my ($filled, $cancelled) = @_;

        # fully filled while we are cancelling
        return $summary->($filled, $cancelled)
            unless $cancelled;

        my $new_o = { %{$o->{order}} };
        $new_o->{price} = $price if defined $price;
        $new_o->{qty} = $qty ? $qty - $filled : $cancelled;
#        warn "resubmitting updated order: ".Dumper($new_o);use Data::Dumper;
        my $new = $self->orders->{$id} =
            $self->submit_order( $new_o,
                                 on_summary => $summary,
                                 on_error => $o->{on_error},
                                 on_match => $o->{on_match},
                                 on_ready => !$new_o->{_updated} ? sub {
                                     my $status = shift;
                                     # warn "==> status after update: $status";
                                     # $status = 'updated' if $status eq 'new' || $status eq 'submitted';
                                     $o->{on_ready}->($status);
                                 } : $o->{on_ready} );
        # maintain original order state
        $new->{matched} = $o->{matched};
        $new->{order}{qty} += $o->{matched};
        $new->{price_sum} = $o->{price_sum};
        $new->{last_fill_time} = $o->{last_fill_time};
        $new_o->{_updated} = 1;
        $cb->('updated');
        delete $o->{on_summary};

    };
    $self->cancel_order($o->{order}{id}, sub {
                            # XXX need to revert?
#                            warn "==> updating: ".$_[0];
                        });
};

__PACKAGE__
