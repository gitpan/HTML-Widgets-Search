package HTML::Widgets::Search;

use strict;
use DBI;
use URI;
use Carp;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %FIELD_OK $AUTOLOAD 
			%FIELD_READ_ONLY $DEBUG);

require Exporter;
require AutoLoader;

@ISA = qw(Exporter AutoLoader);
# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.
@EXPORT = qw(
	
);
$VERSION = '0.06';

  
for my $attr (qw( query field_id start limit form_fields dbh DEBUG
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
	bless $self,$class;
	$self->n_rows;
	return $self;
}

sub header {
	my $self=shift;
	my ($text,$previous,$next)=@_;
	$text=$self->current_start."  - ".
			$self->current_end.
			'( '.$self->n_rows.')' unless defined $text;
	$previous="previous" unless defined $previous;
	$next = "next" unless defined $next;
	my $ret = "<TABLE><TR><TD>$text</TD>";
	if ($self->current_start > 1) {
		$ret.="<TD>".$self->prev(submit => "<INPUT TYPE=\"IMAGE\"
                                                SRC=\"/img/prev.gif\"
                                               NAME=\"$previous\" BORDER=0>").
				"</TD>";
	}
	if ($self->current_end < $self->n_rows) {
		$ret.="<TD>".$self->next(submit => "<INPUT TYPE=\"IMAGE\"
                                                SRC=\"/img/next.gif\"
                                               NAME=\"$next\" BORDER=0>").
				"</TD>";
	}
	return "$ret</TR></TABLE>";
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

sub href {

	my $self=shift;
	my %args=@_;
	my $link_args;
	my $uri;
	if (exists $args{uri}) {
		$uri=URI->new($args{uri});
		$link_args=$args{args};
	} else {
		$uri=URI->new($ENV{REQUEST_URI});
		$link_args=\%args
	}
    $link_args->{_limit}=$self->{limit} if exists $self->{limit};
    $link_args->{_start}=$self->{start};
	$uri->query_form(%$link_args);
	return $uri->as_string();
}

sub form_args_html {
	my $self=shift;
	return '<form method="post">'.$self->args_html(@_)."</form>";

}

sub args_html {
	my $self=shift;
	my %arg=@_;
	$arg{start}=$self->{start} unless exists $arg{start};
	my $ret='';
	foreach (keys %{$self->{form_fields}}) {
		next unless exists $self->{form_fields}->{$_} 
			&&length $self->{form_fields}->{$_};
		next unless /^[a-z0-9_]*$/i; # must be a valid SQL table field name
		$ret.="<INPUT TYPE=HIDDEN NAME=\"$_\" ".
				" VALUE=\"$self->{form_fields}->{$_}\">";
	}
	foreach (keys %{$arg{hidden}}) {
		$ret.="<INPUT TYPE=\"HIDDEN\" NAME=\"$_\"	".
				" VALUE =\"$arg{hidden}->{$_}\">\n"
	}
    $ret.='<INPUT TYPE="HIDDEN" NAME="_start"'.
            " VALUE=\"$arg{start}\">";
    $ret.=" <INPUT TYPE=\"HIDDEN\" NAME=\"_limit\"".
            " VALUE=\"$self->{limit}\">" if exists $self->{limit};

	$ret.=$arg{submit} if exists $arg{submit};

	return $ret;
	
}


sub html_form_fields {
	my $self=shift;
	return $self->args_html(
		start => $self->{start}
	);
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
	$query=~s/(\s*SELECT)\s+(.*?)\s+(FROM .*$)/$1 count($2) $3/i; 
	$query=~s/order by.*//i;
	$query =~ s/count\((.*?,.*?)\)/count(*)/;
	warn $query if $DEBUG;
	my $sth=$self->{dbh}->prepare($query) or die $DBI::errstr;
	$sth->execute or die $DBI::errstr;
	($self->{n_rows}) = $sth->fetchrow;
	$sth->finish;
	$self->{current_end}=$self->{start}+$self->{limit};
	$self->{current_end}=$self->{n_rows}
		if $self->{n_rows}<$self->{current_end};
	$self->{current_start}=($self->{start} + 1);
	return $self->{n_rows};
}

sub fetchrow_hashref {
	my $self=shift;
        if (defined $self->{sth}) {
                return if $self->{dbh}->{Driver}->{Name} ne "mysql"
                                and ($self->{current} > ($self->{start} 
					+ $self->{limit}));
                $self->{current}++;
                return $self->{sth}->fetchrow_hashref;
        }
        my $query=$self->{query};
        $query.=" LIMIT ".$self->{start}.",".$self->{limit}
                if defined $self->{limit} and $self->{dbh}->{Driver}->{Name} eq "mysql";
		warn $query if $DEBUG;
        $self->{sth}=$self->{dbh}->prepare($query) or die $DBI::errstr;
        $self->{sth}->execute or die $DBI::errstr;
        my $row;
        $self->{current}=0;
        while ($row=$self->{sth}->fetchrow_hashref) {
                last if $self->{dbh}->{Driver}->{Name} eq "mysql";
                next if $self->{dbh}->{Driver}->{Name} ne "mysql"
                                and ($self->{current}++ < $self->{start});
                last if $self->{dbh}->{Driver}->{Name} ne "mysql"
                                and ($self->{current} > ($self->{start} 
								+ $self->{limit}));
                last if $self->{dbh}->{Driver}->{Name} ne "mysql";
        }
        return $row;
}

sub fetchrow {
	my $self=shift;
	if (defined $self->{sth}) {
		return if $self->{dbh}->{Driver}->{Name} ne "mysql"
				and ($self->{current} > ($self->{start} 
							+ $self->{limit}));
		$self->{current}++;
		return $self->{sth}->fetchrow;
	}
	my $query=$self->{query};
	$query.=" LIMIT ".$self->{start}.",".$self->{limit}
		if defined $self->{limit} and $self->{dbh}->{Driver}->{Name} eq "mysql";
	warn $query if $DEBUG;
	$self->{sth}=$self->{dbh}->prepare($query) or die $DBI::errstr;
	$self->{sth}->execute or die ("\n$query\n\t$DBI::errstr");
	my @row;
	$self->{current}=0;
	while (@row=$self->{sth}->fetchrow) {
		last if $self->{dbh}->{Driver}->{Name} eq "mysql";
		next if $self->{dbh}->{Driver}->{Name} ne "mysql"
				and ($self->{current}++ < $self->{start});
		last if $self->{dbh}->{Driver}->{Name} ne "mysql"
				and ($self->{current} > ($self->{start} + $self->{limit}));
		last if $self->{dbh}->{Driver}->{Name} ne "mysql";
	}
	return @row;
}

sub render_table {
	my $self=shift;
	my %arg=@_;
	my $query=$self->{query};
	$query.=" LIMIT ".$self->{start}.",".$self->{limit}
		if defined $self->{limit} and $self->{dbh}->{Driver}->{Name} eq "mysql";
	warn $query if $DEBUG;
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
               limit => 10,
         form_fields => \%ARGS,
                 dbh => $dbh
    );
    </%perl>

	<% $search->n_found %> customers found
	<% $search->current_start %> to <% $search -> current_end %><BR>

	<% $search->head %>
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
	

=head1 METHODS

=over

=item *
B<html_form_fields> : Returns the hidden fields necessary if you want to make a form
yourself.

I<Example:>

  <form method="post">

     <input type="submit">

     <% $search -> html_form_fields %>

  </form>


If you don't add the I<html_form_fields> method the search will the
reset to the very first position. Doing it like the example the search
current position will be kept. I don't know how to explain better,
please gimme a hint.

=item *
B<href> : returns a I<href> html tag with the params you send and
	the params needed to reload the current state of the search

I<Example:>

  $search->href( name1 => 'value1' , name2 => 'value2' )

    returns:

  <a href="current_page.html?name1=value1&...I<current state params>">

So the current page will be reloaded with some new values in some arguments.


If you don't want to call the current page you must call it this way:

   $search-> href( url => 'http://another_site/cgi-bin/file.cgi',
                   args => {
						name1 => 'value1',
						name2 => 'value2'
                   }
   );




=back


=head1 TODO

    Improve the docs. You can help me !

=head1 AUTHOR

Francesc Guasch  frankie@etsetb.upc.es

=head1 SEE ALSO

perl(1) , DBI.

=cut
