package HTML::Widgets::Search;

use strict;
use DBI;
use URI;
use Carp;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %FIELD_OK $AUTOLOAD 
			%FIELD_READ_ONLY);

require Exporter;
require AutoLoader;

@ISA = qw(Exporter AutoLoader);
# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.
@EXPORT = qw(
	
);
$VERSION = '0.02';

  
for my $attr (qw( query field_id start limit form_fields dbh 
					current_start current_end spanish_date)) {
	$FIELD_OK{$attr}++; # Los ponemos en ok
}


# Preloaded methods go here.

sub AUTOLOAD {
	my $self=shift;
	my $attr=$AUTOLOAD;
	$attr=~s/.*:://;
	return unless $attr=~/[^A-Z]/;
	croak "Invalid attribute method: ->$attr()" unless $FIELD_OK{$attr};
   if (@_) {
		croak "Trying to write to read only field $attr"
			if exists $FIELD_READ_ONLY{$attr};
		$self->{$attr}=shift;
	}
	return $self->{$attr};   # Devolvemos el valor
}

sub new {
	my $proto=shift;
	my $class=ref($proto) || $proto;
 
	my %arg=@_;# Cojemos los parametros
	my $self={};
	
	foreach (keys %arg) {
		croak "Field invalid: $_ " unless exists $FIELD_OK{$_};
		$self->{$_}=$arg{$_};
	}

	$self->{start}=$self->{form_fields}->{_start} 
		if exists $self->{form_fields}->{_start};
	$self->{limit}=$self->{form_fields}->{_limit} 
		if exists $self->{form_fields}->{_limit}
			and not exists $self->{limit};
	delete $self->{form_fields}->{_start};
	delete $self->{form_fields}->{_limit};


	$self->{start}=0 if exists $self->{limit} and not exists $self->{start};
	return bless $self,$class;
}

sub prev {
	my $self=shift;
	return $self->prev_link(@_);
}

sub next {
	my $self=shift;
	return $self->next_link(@_);;
}


sub prev_link {
	my $self=shift;
	return $self->prev_link_post(@_) if scalar @_ >1;
	my $url=(shift or "");
	my $uri=URI->new($url);
	my %args=%{$self->{form_fields}};
	$args{_limit}=$self->{limit} if exists $self->{limit};
	$args{_start}=$self->{start}-$self->{limit} if exists $self->{start};
	$args{_start}=0 if $args{_start}<0;
	$uri->query_form(%args);
	return $uri->as_string();
}

sub form_args_html {
	my $self=shift;
	my %arg=@_;
	my $ret='<FORM METHOD="POST">';
	foreach (keys %{$self->{form_fields}}) {
		next unless length $self->{form_fields}->{$_};
		next unless /^[a-z0-9_]*$/i; # must be a valid SQL table field name
		$ret.="<INPUT TYPE=HIDDEN NAME=\"$_\" ".
				" VALUE=\"$self->{form_fields}->{$_}\">";
	}
	return $ret.$arg{submit}.
		" <INPUT TYPE=\"HIDDEN\" NAME=\"_start\" 
								VALUE=\"$arg{start}\">".
		" <INPUT TYPE=\"HIDDEN\" NAME=\"_limit\"
								VALUE=\"$self->{limit}\">".
		"</FORM>";
	
}

sub next_link_post {
	my $self=shift;
	croak "Can't do next unless defined start and limit"
		unless exists $self->{limit} and defined $self->{limit}
			and exists $self->{start} and defined $self->{start};
	return $self->form_args_html( @_,
							start => $self->{start}+$self->{limit}
	);
}

sub prev_link_post {
	my $self=shift;
    croak "Can't do prev unless defined start and limit"
        unless exists $self->{limit} and defined $self->{limit}
            and exists $self->{start} and defined $self->{start};
	
    return $self->form_args_html( @_,
								start=>$self->start - $self->limit);
}



sub next_link  {
	my $self=shift;
	return $self->next_link_post(@_) if (scalar(@_) >1);
	my $url=(shift or "");
	my $uri=URI->new($url);
	my %args=%{$self->{form_fields}};
	$args{_limit}=$self->{limit} if exists $self->{limit};
	$args{_start}=$self->{start}+$self->{limit} 
		if exists $self->{start};
	$uri->query_form(%args);
	return $uri->as_string();
}

sub n_rows {
	my $self=shift;
	return $self->{n_rows} if exists $self->{n_rows};
	my $query=$self->{query};
	$query=~s/\n//g;
	$query=~s/(\s*SELECT).*?(FROM .*$)/$1 count(*) $2/i; 
	my $sth=$self->{dbh}->prepare($query) or die $DBI::errstr;
	$sth->execute or die $DBI::errstr;
	($self->{n_rows}) = $sth->fetchrow;
	$sth->finish;
	$self->{current_end}=$self->{start}+$self->{limit};
	$self->{current_end}=$self->{n_rows}
		if $self->{n_rows}<$self->{current_end};
	$self->{current_start}=($self->{start} or 1);
	return $self->{n_rows};
}

sub fetchrow {
	my $self=shift;
	if (defined $self->{sth}) {
		return if $self->{dbh}->{Driver}->{Name} ne "mysql"
				and ($self->{current} > ($self->{start} + $self->{limit}));
		$self->{current}++;
		return $self->{sth}->fetchrow;
	}
	my $query=$self->{query};
	$query.=" LIMIT ".$self->{start}.",".$self->{limit}
		if defined $self->{limit} and $self->{dbh}->{Driver}->{Name} eq "mysql";
	$self->{sth}=$self->{dbh}->prepare($query) or die $DBI::errstr;
	$self->{sth}->execute or die $DBI::errstr;
	my @row;
	$self->{current}=0;
	while (@row=$self->{sth}->fetchrow) {
		last if $self->{dbh}->{Driver}->{Name} eq "mysql";
		next if $self->{dbh}->{Driver}->{Name} ne "mysql"
				and ($self->{current}++ < $self->{start});
		last if $self->{dbh}->{Driver}->{Name} ne "mysql"
				and ($self->{current} > ($self->{start} + $self->{limit}));
	}
	return @row;
}

sub render_table {
	my $self=shift;
	my %arg=@_;
	my $query=$self->{query};
	$query.=" LIMIT ".$self->{start}.",".$self->{limit}
		if defined $self->{limit} and $self->{dbh}->{Driver}->{Name} eq "mysql";
	my $sth=$self->{dbh}->prepare($query) or die $DBI::errstr;
	my $html="";
	$sth->execute or die $DBI::errstr;
	my @row;
	my $cont=0;
	while (@row=$sth->fetchrow) {
		next if $self->{dbh}->{Driver}->{Name} ne "mysql"
				and ($cont++ < $self->{start});
		last if $self->{dbh}->{Driver}->{Name} ne "mysql"
				and ($cont > ($self->{start} + $self->{limit}));
		$html.="<TR>";
		my $nfield=0;
		foreach (@row) {
			$nfield++;
			next if $nfield==1 and defined $arg{link};
			$_="" unless defined;
			unless  (defined $arg{link}) {
				$html.="<TD>$_</TD>";
			} else {
				$html.="<TD><A HREF=\"$arg{link}?$self->{field_id}=$row[0]\">";
				$html.=$self->draw($_);
				$html.="</A></TD>";
			}
		}
		$html.="</TR>";
	}
	$sth->finish;
	return $html;
}

############ Draw data helper functions

sub draw {
	my $self=shift;
	my ($text)=@_;
	return spanish_date($text) 
		if 	exists $self->{spanish_date} and $self->{spanish_date}
			and $text=~/\d{4}-\d{2}-\d{2}/;
	return $text;
}

sub spanish_date {

	my ($date)=@_;
	$date=~s/-0(\d)/-$1/g;
	my ($any,$mes,$dia)=split /-/,$date;
	return "$dia-$mes-$any";

}

# Autoload methods go after =cut, and are processed by the autosplit program.

1;
__END__
# Below is the stub of documentation for your module. You better edit it!

=head1 NAME

HTML::Widgets::Search - Perl module for building searches returning HTML

=head1 SYNOPSIS

    <%perl>
    use HTML::Widgets::Search;
    my $search=HTML::Widgets::Search->new(
               query => "SELECT idCustomer,name               ".
                        " FROM customers WHERE name LIKE 'a%' ".
                        " ORDER BY name                       ",
            field_id => "idCustomer",
               limit => "10",
         form_fields => \%fields,
                 dbh => $dbh
    );
    </%perl>

	<% $search->n_found %> customers found
	<% $search->current_start %> to <% $search -> current_end %><BR>
    <TABLE WIDTH="90%">
        <%perl>
             $search->render_table(
                 link=>"http://www.me.com/show_customer.html"
             );
        </%perl>
    </TABLE>

    <A HREF="search_customer.html<% $search->next %>">next</A>

    <A HREF="search_customer.html<% $search->prev %>">previous</A>

    <% $search->prev(submit => '<INPUT 	TYPE="IMAGE" 
                                SRC="/img/prev.gif"  
                                NAME="previous" BORDER=0>')
	%>
    %#################################################################3
    <TABLE>
    % while (my @row=$search->fetchrow) {
        <TR><TD>
            <% join "</TD><TD>", @row %>
        </TD></TR>
    % }
    </TABLE>

=head1 DESCRIPTION

    The programmer designs a html form with some field values, then
    you can write a sql query using those fields.


	The constuctor requires a SQL statement and a valid DBI object.

    render_table returns a HTML table with the results , if a link
    is provided every field of the table has that link. If a field_id
	is provided the link adds that field as a parameter. This field
	must be the first field of the select query and is discarded in
	the render.

    Supports native mysql limit clauses. For other DBs skips untill start
    and fetches until limit.

	Give it a try, the synopsis may help you start.
	Let me know if it's useful for or whatever you want to tell me.
	


=head1 TODO

    Improve the docs. You can help me !

=head1 AUTHOR

Francesc Guasch  frankie@etsetb.upc.es

=head1 SEE ALSO

perl(1) , DBI.

=cut
