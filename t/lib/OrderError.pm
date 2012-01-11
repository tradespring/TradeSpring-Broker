package OrderError;
use Moose::Role;

has qty_limit => (is => "rw", isa => "Int", default => sub { 1 });
has extra_price_on_cancel => (is => "rw", isa => "Bool");

around submit_order => sub {
    my ($next, $self, @args) = @_;
    my $o = $self->$next(@args);
    return $o unless $o->{order}{type} eq 'mkt';
    my $id = $o->{order}{id};
    $o->{execute} = sub { 0 };
    my $w; $w = AnyEvent->timer(after => 0.5,
                    cb => sub {
                        $o->{on_error}->('Fail', 'hate software');
                        $o->{on_summary}->($o->{matched}, $o->{order}{qty} - $o->{matched});
                        undef $w;
                    });

    return $o;
};

1;
