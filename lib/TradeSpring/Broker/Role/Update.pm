package TradeSpring::Broker::Role::Update;
use Moose::Role;
use Method::Signatures::Simple;

method update_order($id, $price, $qty, $cb) {
    my $o = $self->get_order($id);

    my $summary = $o->{on_summary};

    $o->{on_summary} = sub {
        my ($filled, $cancelled) = @_;
        my $new_o = { %{$o->{order}} };
        $new_o->{price} = $price if defined $price;
        $new_o->{qty} = $qty ? $qty : $cancelled;
#        warn "resubmitting updated order: ".Dumper($new_o);use Data::Dumper;
        $self->orders->{$id} = $self->submit_order( $new_o,
                                                    on_summary => $summary,
                                                    on_match => $o->{on_match},
                                                    on_ready => !$new_o->{_updated} ? sub {
                                                        my $status = shift;
#                                                        warn "==> status after update: $status";
                                                        $status = 'updated' if $status eq 'new' || $status eq 'submitted';
                                                        $o->{on_ready}->($status);
                                                    } : $new_o->{on_ready} );
        $new_o->{_updated} = 1;
        $cb->('updated');
    };
    $self->cancel_order($o->{order}{id}, sub {
                            # XXX need to revert?
#                            warn "==> updating: ".$_[0];
                        });
}

__PACKAGE__
