package Test::Database::Driver;
use strict;
use warnings;
use Carp;
use File::Spec;
use File::Path;
use version;

#
# global configuration
#
# the location where all drivers-related files will be stored
my $root
    = File::Spec->rel2abs(
    File::Spec->catdir( File::Spec->tmpdir(), 'Test-Database-' . getlogin() )
    );

# some information stores, indexed by driver class name
my %drh;

# generic driver class initialisation
sub __init {
    my ($class) = @_;

    # create directory if needed
    my $dir = $class->base_dir();
    if ( !-e $dir ) {
        mkpath [$dir];
    }
    elsif ( !-d $dir ) {
        croak "$dir is not a directory. Initializing $class failed";
    }

    # load the DBI driver
    $drh{ $class->name() } ||= DBI->install_driver( $class->name() );
}

sub new {
    my ( $class, %args ) = @_;

    if ( $class eq __PACKAGE__ ) {
        croak "No driver defined" if !exists $args{driver};
        eval "require Test::Database::Driver::$args{driver}"
            or croak $@;
        $class = "Test::Database::Driver::$args{driver}";
        $class->__init();    # survive a cleanup()
    }
    bless {
        username => '',
        password => '',
        %args,
        driver => $class->name()
        },
        $class;
}

#
# accessors
#
sub name { return ( $_[0] =~ /^Test::Database::Driver::([:\w]*)/g )[0]; }

sub base_dir {
    return $_[0] eq __PACKAGE__
        ? $root
        : File::Spec->catdir( $root, $_[0]->name() );
}

sub version {
    no warnings;
    return $_[0]{version} ||= version->new( $_[0]->_version() );
}

sub drh      { return $drh{ $_[0]->name() } }
sub dsn      { return $_[0]{dsn} ||= $_[0]->_dsn() }
sub username { return $_[0]{username} }
sub password { return $_[0]{password} }

sub connection_info {
    return ( $_[0]->dsn(), $_[0]->username(), $_[0]->password() );
}

sub cleanup { rmtree $_[0]->base_dir(); }

sub _filebased_databases {
    my ($self) = @_;
    my $dir = $self->base_dir();

    opendir my $dh, $dir or croak "Can't open directory $dir for reading: $!";
    my @databases = File::Spec->no_upwards( readdir($dh) );
    closedir $dh;

    return @databases;
}

sub available_dbname {
    my ($self) = @_;
    my $name = join '_', 'Test', 'Database', $self->name(), '0';
    my %taken = map { $_ => 1 } $self->databases();
    $name++ while $taken{$name};
    return $name;
}

sub _quote {
    my ($string) = @_;
    return $string if $string =~ /^\w+$/;

    $string =~ s/\\/\\\\/g;
    $string =~ s/"/\\"/g;
    $string =~ s/\n/\\n/g;
    return qq<"$string">;
}

sub _unquote {
    my ($string) = @_;
    return $string if $string !~ /\A(["']).*\1\z/s;

    my $quote = chop $string;
    $string = substr( $string, 1);
    $string =~ s/\\(.)/$1 eq 'n' ? "\n" : $1/eg;
    return $string;
}

sub as_string {
    return join '',
        map { "$_ = " . _quote( $_[0]{$_} || '' ) . "\n" }
        driver => $_[0]->essentials();
}

# THESE MUST BE IMPLEMENTED IN THE DERIVED CLASSES
sub create_database { die "$_[0] doesn't have a create_database() method\n" }
sub drop_database   { die "$_[0] doesn't have a drop_database() method\n" }
sub _version        { die "$_[0] doesn't have a _version() method\n" }

sub databases {
    goto &_filebased_databases if $_[0]->is_filebased();
    die "$_[0] doesn't have a databases() method\n";
}

# THESE MAY BE OVERRIDDEN IN THE DERIVED CLASSES
sub essentials   { }
sub is_filebased {0}
sub _dsn         { join ':', 'dbi', $_[0]->name(), ''; }

'CONNECTION';

__END__

=head1 NAME

Test::Database::Driver - Base class for Test::Database drivers

=head1 SYNOPSIS

    package Test::Database::Driver::MyDatabase;
    use strict;
    use warnings;

    use Test::Database::Driver;
    our @ISA = qw( Test::Database::Driver );

    sub _version {
        my ($class) = @_;
        ...;
        return $version;
    }

    sub create_database {
        my ( $class, $name ) = @_;
        ...;
        return $handle;
    }

    sub drop_database {
        my ( $class, $name ) = @_;
        ...;
    }

    sub databases {
        my ($class) = @_;
        ...;
        return @databases;
    }

=head1 DESCRIPTION

C<Test::Database::Driver> is a base class for creating C<Test::Database>
drivers.

=head1 METHODS

The class provides the following methods:

=over 4

=item new( %args )

Create a new C<Test::Database::Driver> object.

If called as C<< Test::Database::Driver->new() >>, requires a C<driver>
parameter to define the actual object class.

=item name()

The driver's short name (everything after C<Test::Database::Driver::>).

=item base_dir()

The directory where the driver should store all the files for its databases,
if needed. Typically used by file-based database drivers.

=item version()

C<version> object representing the version of the underlying database enginge.
This object is build with the return value of C<_version()>.

=item drh()

The DBI driver for this driver.

=item dsn()

Return the Data Source Name.

=item username()

Return the connection username.

=item password()

Return the connection password.

=item connection_info()

Return the connection information triplet (C<dsn>, C<username>, C<password>).

=item is_filebased()

Return a boolean value indicating if the database engine is file-based
or not, i.e. if all the database information is stored in a file or a
directory, and no external database server is needed.

=item as_string()

Return a string representation of the C<Test::Database::Driver>,
suitable to be saved in a configuration file.

=item cleanup()

Remove the directory used by C<Test::Database> drivers.

=back

The class also provides a few helpful commands that may be useful for driver
authors:

=over 4

=item __init()

The method does the general configuration needed for a database driver.
All drivers should start by calling C<< __PACKAGE__->__init() >> to ensure
they have been correctly initialized.

=back

=head1 WRITING A DRIVER FOR YOUR DATABASE OF CHOICE

The L<SYNOPSIS> contains a good template for writing a
C<Test::Database::Driver> class.

Creating a driver requires writing the following methods:

=over 4

=item _version()

Return the version of the underlying database engine.

=item create_database( $name )

Create the database for the corresponding DBD driver.

Return a C<Test::Database::Handle> in case of success, and nothing in
case of failure to create the database.

=item drop_database( $name )

Drop the database named C<$name>.

=back

Some methods have defaults implementations in C<Test::Database::Driver>,
but those can be overridden in the derived class:

=over 4

=item essentials()

Return the I<essential> fields needed to serialize the driver.

=item databases()

Return the names of all existing databases for this driver as a list
(the default implementation is only valid for file-based drivers).

=back

=head1 AUTHOR

Philippe Bruhat (BooK), C<< <book@cpan.org> >>

=head1 COPYRIGHT

Copyright 2008-2009 Philippe Bruhat (BooK), all rights reserved.

=head1 LICENSE

This module is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

