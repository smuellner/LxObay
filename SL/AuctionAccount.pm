package SL::AuctionAccount;

use strict;

use SL::DBUtils;

sub save {
  $main::lxdebug->enter_sub();

  my $self     = shift;
  my %params   = @_;

  my $myconfig = \%main::myconfig;
  my $form     = $main::form;

  my $dbh      = $params{dbh} || $form->get_standard_dbh($myconfig);
    
  $params{id} = 0;

  my $query    = qq|SELECT * FROM auction_accounts WHERE id = ?|;
  my $account  = selectfirst_hashref_query($form, $dbh, $query, conv_i($params{id}));
  
  if(!$account) {
    do_query($form, $dbh, qq|INSERT INTO auction_accounts (id, platform) VALUES (?, ?)|, conv_i($params{id}), $params{platform});
  }

  my $query =
    qq|UPDATE auction_accounts
       SET username = ?, auth_token = ?, hard_expiration_time = ?, platform = ?
       WHERE id = ?|;
  my @values = (@params{qw(username auth_token hard_expiration_time platform)}, conv_i($params{id}));

  do_query($form, $dbh, $query, @values);

  $dbh->commit() unless ($params{dbh});

  $main::lxdebug->leave_sub();

  return $params{id};
}

sub retrieve {
  $main::lxdebug->enter_sub();

  my $self     = shift;
  my %params   = @_;

  Common::check_params(\%params, qw(id));

  my $myconfig = \%main::myconfig;
  my $form     = $main::form;

  my $dbh      = $params{dbh} || $form->get_standard_dbh($myconfig);

  my $query    = qq|SELECT * FROM auction_accounts WHERE id = ?|;
  
  my $account  = selectfirst_hashref_query($form, $dbh, $query, conv_i($params{id}));
  
  if(!$account) {
 	$account->{ 'platform' } = '0';
  	$account->{ 'username' } = '';
  	$account->{ 'auth_token' } = '';
  	$account->{ 'hard_expiration_time' } = '';
  }
  $main::lxdebug->leave_sub();

  return $account;
}

1;
