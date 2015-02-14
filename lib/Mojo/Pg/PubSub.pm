package Mojo::Pg::PubSub;
use Mojo::Base 'Mojo::EventEmitter';

use Scalar::Util 'weaken';

has 'pg';

sub is_listening {
  !!eval { shift->_db };
}

sub listen {
  my ($self, $name, $cb) = @_;
  $self->_db->listen($name) unless @{$self->{chans}{$name} ||= []};
  push @{$self->{chans}{$name}}, $cb;
  return $cb;
}

sub notify { $_[0]->_db->notify(@_[1, 2]) and return $_[0] }

sub unlisten {
  my ($self, $name, $cb) = @_;
  my $chan = $self->{chans}{$name};
  @$chan = grep { $cb ne $_ } @$chan;
  $self->_db->unlisten($name) and delete $self->{chans}{$name} unless @$chan;
  return $self;
}

sub _db {
  my $self = shift;

  return $self->{db} if $self->{db};

  $self->emit(reconnect => my $db = $self->{db} = $self->pg->db);
  weaken $self;
  $db->on(
    notification => sub {
      my ($db, $name, $pid, $payload) = @_;
      for my $cb (@{$self->{chans}{$name}}) { $self->$cb($payload) }
    }
  );
  $db->once(close => sub { delete $self->{db}; $self->is_listening });
  $db->listen($_) for keys %{$self->{chans}};

  return $db;
}

1;

=encoding utf8

=head1 NAME

Mojo::Pg::PubSub - Publish/Subscribe

=head1 SYNOPSIS

  use Mojo::Pg::PubSub;

  my $pubsub = Mojo::Pg::PubSub->new(pg => $pg);
  my $cb = $pubsub->listen(foo => sub {
    my ($pubsub, $payload) = @_;
    say "Received: $payload";
  });
  $pubsub->notify(foo => 'bar');
  $pubsub->unlisten(foo => $cb);

=head1 DESCRIPTION

L<Mojo::Pg::PubSub> is a scalable implementation of the publish/subscribe
pattern based on PostgreSQL notifications. It allows many consumers to share
the same database connection and is therefore very efficient, avoiding common
scalability problems.

=head1 EVENTS

L<Mojo::Pg::PubSub> inherits all events from L<Mojo::EventEmitter> and can
emit the following new ones.

=head2 reconnect

  $pubsub->on(reconnect => sub {
    my ($pubsub, $db) = @_;
    ...
  });

Emitted when a new database connection has been established.

=head1 ATTRIBUTES

L<Mojo::Pg::PubSub> implements the following attributes.

=head2 pg

  my $pg  = $pubsub->pg;
  $pubsub = $pubsub->pg(Mojo::Pg->new);

L<Mojo::Pg> object this publish/subscribe container belongs to.

=head1 METHODS

L<Mojo::Pg::PubSub> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 is_listening

  my $bool = $pubsub->is_listening;

Check if a database connection can be established.

=head2 listen

  my $cb = $pubsub->listen(foo => sub {...});

Subscribe to a channel.

=head2 notify

  $pubsub = $pubsub->notify(foo => 'bar');

Notify a channel.

=head2 unlisten

  $pubsub = $pubsub->unlisten(foo => $cb);

Unsubscribe from a channel.

=head1 SEE ALSO

L<Mojo::Pg>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
