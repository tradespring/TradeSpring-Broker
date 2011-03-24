package TradeSpring::Broker::Role::Position;
use Moose::Role;
use Method::Signatures::Simple;
use Hash::Util::FieldHash qw(id);

requires 'on_price';

has position => (is => "rw", isa => "Int", default => sub { 0 },
                 writer => 'set_position');

has position_effect_open  => (is => "rw", isa => "Str", default => sub { 'Open' });
has position_effect_close => (is => "rw", isa => "Str", default => sub { 'Close' });

around 'submit_order' => sub {
    my $next = shift;
    my ($self, $order, %args) = @_;
    $order->{position} =
        $self->position * $order->{dir} >= 0 ? $self->position_effect_open : $self->position_effect_close;

    return $next->(@_);
};

before fill_order => method($o, $price, $qty, $meta) {
    my $old_pos = $self->position;
    $self->set_position( $old_pos + $o->{order}{dir} * $qty );
    $self->log->info("Broker position update on fill $price/$qty: $old_pos -> ".$self->position);
};

__PACKAGE__
