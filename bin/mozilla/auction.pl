#=====================================================================
# LX-Office ERP
# Copyright (C) 2004
# Based on SQL-Ledger Version 2.1.9
# Web http://www.lx-office.org
#############################################################################
# SQL-Ledger, Accounting
# Copyright (c) 1998-2002
#
#  Author: Dieter Simader
#   Email: dsimader@sql-ledger.org
#     Web: http://www.sql-ledger.org
#
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#
#######################################################################
#
# auction managment (ebay)
#
#######################################################################

use List::Util qw(min max first);
use POSIX qw(strftime);
use Date::Parse;
use Date::Format;
use Date::Language;
use Time::Local;

use SL::Form;
use SL::User;

use SL::AM;
use SL::CT;
use SL::IC;
use SL::WH;
use SL::OE;
use SL::ReportGenerator;
use SL::AuctionAccount;

use Data::Dumper;

use eBay::API::Simple::Trading;
use eBay::API::Simple::Merchandising;
use eBay::API::Simple::Auth;

require "bin/mozilla/common.pl";
require "bin/mozilla/reportgenerator.pl";
use Encode;
use utf8;
use strict;

# parserhappy(R):

# contents of the "transfer_type" table:
#  $locale->text('back')
#  $locale->text('correction')
#  $locale->text('disposed')
#  $locale->text('found')
#  $locale->text('missing')
#  $locale->text('stock')
#  $locale->text('shipped')
#  $locale->text('transfer')
#  $locale->text('used')
#  $locale->text('return_material')
#  $locale->text('release_material')

# --------------------------------------------------------------------
# Auctions
# --------------------------------------------------------------------

sub char_encode {
   my($inString) = @_;
   my $outString = decode("iso-8859-1", $inString); 
   return $outString;
}

sub timestamp_str {
        my($timestamp) = @_;
        my $lang = Date::Language->new('German');
	if($timestamp) {
        	return $lang->time2str("%a %b %e %T %Y", $timestamp);
	}
	return "";
}  

sub ebay_timestamp {
   my($inVar) = @_;
   # 2010-12-11T20:43:21.000Z
   my $time;
   $time = str2time($inVar);
   return $time;	
}

sub ebay_timestamp_str {
	my($inVar) = @_;
	my $ebay_timestamp = ebay_timestamp($inVar);
	my $lang = Date::Language->new('German');
        return $lang->time2str("%a %b %e %T %Y", $ebay_timestamp);
}

sub alltrim($){
    my $s = shift;
    $s =~ s/^\s*//;
    $s =~ s/\s*$//;
    return $s;
}
   
sub running_auctions {

  $main::lxdebug->enter_sub();
  # $main::auth->assert('running_auctions');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  my $account = SL::AuctionAccount->retrieve('id' => 0);
  
  my $username;
  my $auth_token;
  my $hard_expiration_time;
  if($account && $account->{username} && $account->{auth_token}) {
        # get data
        $username = $account->{username};
        $auth_token = $account->{auth_token};
        $hard_expiration_time = $account->{hard_expiration_time};
        # check if token is still valid
  } else {
	# call method setup
	setup_account();
	return 0;
  }
  $form->{title} = $locale->text('Running Auctions') ." (" . $username . ")";
  $form->header();

###

   my $call = eBay::API::Simple::Trading->new( {
   	appid   => 'Webblaze-42c3-402e-9137-46a2dd82f00b',
    	devid   => '5ffcc3cf-3652-4b56-aafb-5e89d1cf9a56',
    	certid  => 'b9327d52-2328-48e8-bb2b-bd85f29eb985',
      	token   => $auth_token,
   } );

#   use POSIX qw(strftime);
#   my @now = localtime(); ## get the current [sec, min, ...] values
#   my @past = @now; $past[3] -= 60; ## same time, 2 month ago
#   my $datetime = strftime("%Y-%m-%dT%H:%M:%S", @past);


#   $call->execute( 'GetSellerList', { 
#   	Sort 	 	=> 1,
#        UserID   	=> $username,
#	StartTimeFrom	=> $datetime,         
#	StartTimeTo     => $datetime, 
#	Pagination 	=> { EntriesPerPage => 100, PageNumber => 1 },
#     });

   $call->execute( 'GetMyeBaySelling', {
        Sort            => 1,
        UserID          => $username,
        ActiveList      => { Include => "true", IncludeNotes => "true" },
     });

   if ( $call->has_error() ) {
   	print "Call Failed: " . $call->errors_as_string();
   }

  # getters for the response DOM or Hash
  my $dom  = $call->response_dom();
  my $hash = $call->response_hash();
  
  my @pagination = $dom->findnodes(
    '//PaginationResult'
  );

  my $totalNumberOfEntries;
  my $totalNumberOfPages;
  foreach my $p ( @pagination ) {
  	# print "\n<code>" . $p->toString() . "</code>\n\n";
  	$totalNumberOfPages	= $p->findvalue('TotalNumberOfPages/text()');
  	$totalNumberOfEntries	= $p->findvalue('TotalNumberOfEntries/text()');
  }

  if($totalNumberOfEntries >= 1) {
  	my @auctions = ();  # initialize an array to hold your loop
  	my @nodes = $dom->findnodes(
    	  '//Item'
  	);
	my $cnt = 0;
  	foreach my $n ( @nodes ) {
    		# print "\n<code>" . $n->toString() . "</code>\n\n";
    		# create row data
    		my %auction;  # get a fresh hash for the row data
		
    		$auction{id}       	  	= $n->findvalue('ItemID/text()');
		$auction{title}    	  	= $n->findvalue('Title/text()');
                my $private_notes	     	= $n->findvalue('PrivateNotes/text()');
		if($private_notes) {
			my @notes = split(/\n/, $private_notes);
		        foreach my $note_row ( @notes ) {
				my $tag;
				my $value;
  				($tag, $value) = split(/:\s*/, $note_row);	
				if($tag == "ProductNumber") {
					$auction{product_number} = trim($value);
				}
                                if($tag == "Amount") {
	                        	$auction{amount} = trim($value);
                                }
			}
			$auction{private_notes}  = "Product Number: " . $auction{product_number} . "<br />Amount: " . $auction{amount};
		} else {
			$auction{private_notes}  = "No Notes!<br />Please add the product number and the amount e.g.:<br /><code>ProductNumber: Q1A01C03A</code><br /><code>Amount: 3</code>";
		} 
		$auction{quantity}	  	= $n->findvalue('Quantity/text()');
                $auction{quantity_available}	= $n->findvalue('QuantityAvailable/text()');
                $auction{time_left}       	= $n->findvalue('TimeLeft/text()');
                $auction{buy_it_now_price}	= $n->findvalue('BuyItNowPrice/text()');
		if(!$auction{buy_it_now_price}) {
			$auction{buy_it_now_price} = "0.0";
		}
                $auction{start_price}     	= $n->findvalue('StartPrice/text()');

		# ListingDetails
		my @listingDetails 	  = $n->findnodes(
          	  '//ListingDetails'
        	);

		if(@listingDetails) {
			$auction{start_date}      = $listingDetails[$cnt]->findvalue('StartTime/text()');
			$auction{item_url} 	  = $listingDetails[$cnt]->findvalue('ViewItemURL/text()');
		}
                # SellingStatus
                my @sellingStatus         = $n->findnodes(
                  '//SellingStatus'  
                );
		if(@sellingStatus) {
	                $auction{current_price}   = $sellingStatus[$cnt]->findvalue('CurrentPrice/text()');
		}
        
	        # HighBidder
                my @highBidder         		= $n->findnodes(
                  '//HighBidder'
                );
		if(@highBidder) {
               		$auction{user_id}              = $highBidder[$cnt]->findvalue('UserID/text()');
                	$auction{feedback_score}       = $highBidder[$cnt]->findvalue('FeedbackScore/text()');

		}

		# ShippingDetails
                my @shippingDetails       = $n->findnodes(
                  '//ShippingServiceOptions'
                );
		if(@shippingDetails) {
			$auction{shipping_price}  = $shippingDetails[$cnt]->findvalue('ShippingServiceCost/text()');
		}

                # PictureDetails
                my @pictureDetails         = $n->findnodes(
                  '//PictureDetails'
                );
		if(@pictureDetails) {
    			$auction{image_url}       = $pictureDetails[$cnt]->findvalue('GalleryURL/text()');
		}

     		# the crucial step - push a reference to this row into the loop!
     		if(\%auction) {
			push(@auctions, \%auction);
		}
		$cnt++;
  	}

  	$form->{title} = $locale->text('Running Auctions') . "&nbsp\;" . $call->nodeContent( 'timestamp' ) . "&nbsp\;<div align=right>#" . $call->nodeContent( 'totalEntries' ) . "</div>";
  	$form->header();
  	print $form->parse_html_template("auction/running_auctions", { "TITLE" => $form->{title}, "AUCTIONS" => \@auctions });
  } else {
  	$form->{title} = $locale->text('Running Auctions') . "&nbsp\;" . $call->nodeContent( 'timestamp' ) . "&nbsp\;<div align=right>#" . $call->nodeContent( 'totalEntries' ) . "</div>";
  	$form->header();
  	print $form->parse_html_template("auction/running_auctions", { "TITLE" => $form->{title}, "MESSAGE" => "No running auctions found." });
  }
###
  $main::lxdebug->leave_sub();
  
}


sub finished_auctions {

  $main::lxdebug->enter_sub();
  # $main::auth->assert('finished_auctions');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  my $account = SL::AuctionAccount->retrieve('id' => 0);
  
  my $username;
  my $auth_token;
  my $hard_expiration_time;
  if($account && $account->{username} && $account->{auth_token}) {
        # get data
        $username = $account->{username};
        $auth_token = $account->{auth_token};
        $hard_expiration_time = $account->{hard_expiration_time};
        # check if token is still valid
  } else {
	# call method setup
	setup_account();
	return 0;
  }
  $form->{title} = $locale->text('Finished Auctions') ." (" . $username . ")";
  $form->header();


###

   my $call = eBay::API::Simple::Trading->new( {
   	appid   => 'Webblaze-42c3-402e-9137-46a2dd82f00b',
    	devid   => '5ffcc3cf-3652-4b56-aafb-5e89d1cf9a56',
    	certid  => 'b9327d52-2328-48e8-bb2b-bd85f29eb985',
      	token   => $auth_token,
   } );


   $call->execute( 'GetSellerTransactions', {
        UserID          	=> $username,
	IncludeContainingOrder	=> "true",
	NumberOfDays		=> "7",
	DetailLevel		=> "ReturnAll"
     });

   if ( $call->has_error() ) {
   	print "Call Failed: " . $call->errors_as_string();
   }

  # getters for the response DOM or Hash
  my $dom  = $call->response_dom();
  my $hash = $call->response_hash();
  
  my @pagination = $dom->findnodes(
    '//PaginationResult'
  );

  my $totalNumberOfEntries;
  my $totalNumberOfPages;
  foreach my $p ( @pagination ) {
  	# print "\n<code>" . $p->toString() . "</code>\n\n";
  	$totalNumberOfPages		= $p->findvalue('TotalNumberOfPages/text()');
  	$totalNumberOfEntries	= $p->findvalue('TotalNumberOfEntries/text()');
  }

  if($totalNumberOfEntries >= 1) {
  	my @auctions = ();  # initialize an array to hold your loop
  	my @nodes = $dom->findnodes(
    	  '//Transaction'
  	);
	my $cnt = 0;
  	foreach my $n ( @nodes ) {
    		# print "\n<code>" . $n->toString() . "</code>\n\n";
    		# create row data
    		my %auction;  # get a fresh hash for the row data

                $auction{transaction_id}         = $n->findvalue('TransactionID/text()');
                $auction{transaction_price}      = $n->findvalue('TransactionPrice/text()');
		$auction{paid_time}            	 = &ebay_timestamp($n->findvalue('PaidTime/text()'));
                $auction{paid_time_str}          = &timestamp_str($auction{paid_time});
                $auction{shipped_time}           = $n->findvalue('ShippedTime/text()');
                $auction{shipped_time_str}       = &timestamp_str($auction{shipped_time});
                $auction{quantity_purchased}     = $n->findvalue('QuantityPurchased/text()');

                # item
                my @product = $n->findnodes(
                  '//Item'
                );

    		$auction{id}       	  	= $product[$cnt]->findvalue('ItemID/text()');                
		$auction{title}    	  	= char_encode($product[$cnt]->findvalue('Title/text()'));
                my $private_notes	     	= $product[$cnt]->findvalue('PrivateNotes/text()');
		if($private_notes) {
			my @notes = split(/\n/, $private_notes);
		        foreach my $note_row ( @notes ) {
				my $tag;
				my $value;

  				($tag, $value) = split(/:\s*/, $note_row);	
				if($tag == "ProductNumber") {
					$auction{product_number} = trim($value);
				}
                                if($tag == "Amount") {
	                        	$auction{amount} = trim($value);
                                }
			}
			$auction{private_notes}  = "Product Number: " . $auction{product_number} . "<br />Amount: " . $auction{amount};
		} else {
			$auction{private_notes}  = "No Notes!<br />Please add the product number and the amount e.g.:<br /><code>ProductNumber: Q1A01C03A</code><br /><code>Amount: 3</code>";
		} 
		$auction{quantity}	  	= $product[$cnt]->findvalue('Quantity/text()');
                $auction{quantity_available}	= $product[$cnt]->findvalue('QuantityAvailable/text()');
                $auction{time_left}       	= $product[$cnt]->findvalue('TimeLeft/text()');
                $auction{buy_it_now_price}	= $product[$cnt]->findvalue('BuyItNowPrice/text()');
		if(!$auction{buy_it_now_price}) {
			$auction{buy_it_now_price} = "0.0";
		}
                $auction{start_price}     	= $product[$cnt]->findvalue('StartPrice/text()');

		# ListingDetails
		my @listingDetails 	  = $product[$cnt]->findnodes(
          	  '//ListingDetails'
        	);

		if(@listingDetails && $listingDetails[$cnt]) {
			$auction{start_date}      = &ebay_timestamp($listingDetails[$cnt]->findvalue('StartTime/text()'));
                        $auction{start_date_str}  = &timestamp_str($auction{start_date});
			$auction{item_url} 	  = $listingDetails[$cnt]->findvalue('ViewItemURL/text()');
		}
                # SellingStatus
                my @sellingStatus         = $n->findnodes(
                  '//SellingStatus'  
                );
		if(@sellingStatus && $sellingStatus[$cnt]) {
	                $auction{current_price}   = $sellingStatus[$cnt]->findvalue('CurrentPrice/text()');
		}
        
	        # Buyer
                my @buyer  = $n->findnodes(
                  '//Buyer'
                );
		if(@buyer && $buyer[$cnt]) {
               		$auction{buyer_user_id}              = &char_encode($buyer[$cnt]->findvalue('UserID/text()'));
                	$auction{buyer_feedback_score}       = &char_encode($buyer[$cnt]->findvalue('FeedbackScore/text()'));
                        $auction{buyer_email}   	     = &char_encode($buyer[$cnt]->findvalue('Email/text()'));

			# ShippingAddress	
                	my @shippingAddress       	= $buyer[$cnt]->findnodes(
                  		'//ShippingAddress'
                	);
    
	                if(@shippingAddress && $shippingAddress[$cnt]) {
				$auction{buyer_name}      	= &char_encode($shippingAddress[$cnt]->findvalue('Name/text()'));		
                                $auction{buyer_street_1}  	= &char_encode($shippingAddress[$cnt]->findvalue('Street/text()'));
                                $auction{buyer_street_2}  	= &char_encode($shippingAddress[$cnt]->findvalue('Street1/text()'));
                                $auction{buyer_street_3}  	= &char_encode($shippingAddress[$cnt]->findvalue('Street2/text()'));
				$auction{buyer_street}		= &alltrim($auction{buyer_street_1} . " " . $auction{buyer_street_2} . " " . $auction{buyer_street_3});
                                $auction{buyer_postal_code}  	= $shippingAddress[$cnt]->findvalue('PostalCode/text()');
                                $auction{buyer_city}  		= $shippingAddress[$cnt]->findvalue('CityName/text()');
                                $auction{buyer_country}         = $shippingAddress[$cnt]->findvalue('CountryName/text()');
                                $auction{buyer_phone}         	= &char_encode($shippingAddress[$cnt]->findvalue('Phone/text()'));
				if($auction{buyer_phone} == "Invalid Request") {
					$auction{buyer_phone} = "";
				}
                	}
		}

		# ShippingDetails
                my @shippingDetails       = $n->findnodes(
                  '//ShippingServiceOptions'

                );
		if(@shippingDetails && $shippingDetails[$cnt]) {
			$auction{shipping_price}  = $shippingDetails[$cnt]->findvalue('ShippingServiceCost/text()');
		}

		$auction{image_url} = &ebay_gallery_url($auction{id});

     		# the crucial step - push a reference to this row into the loop!
                if(\%auction && !$auction{shipped_time}) {
                        push(@auctions, \%auction);
                }

		$cnt++;

  	}
        # now sort the array
	my @ordered_auctions = sort { $b->{paid_time} <=> $a->{paid_time} } @auctions;

  	$form->{title} = $locale->text('Finished Auctions') . "&nbsp\;" . $call->nodeContent( 'timestamp' ) . "&nbsp\;<div align=right>#" . $call->nodeContent( 'totalEntries' ) . "</div>";
  	$form->header();
  	print $form->parse_html_template("auction/finished_auctions", { "TITLE" => $form->{title}, "AUCTIONS" => \@ordered_auctions });
  } else {
  	$form->{title} = $locale->text('Finished Auctions') . "&nbsp\;" . $call->nodeContent( 'timestamp' ) . "&nbsp\;<div align=right>#" . $call->nodeContent( 'totalEntries' ) . "</div>";
  	$form->header();
  	print $form->parse_html_template("auction/finished_auctions", { "TITLE" => $form->{title}, "MESSAGE" => "No running auctions found." });
  }
###
  $main::lxdebug->leave_sub();
  
}



sub ebay_gallery_url {
  my($itemID) = @_;
  my $account = SL::AuctionAccount->retrieve('id' => 0);
  my $username;         
  my $auth_token;
  my $hard_expiration_time;
  if($account && $account->{username} && $account->{auth_token}) {
        # get data              
        $username = $account->{username};
        $auth_token = $account->{auth_token};
        $hard_expiration_time = $account->{hard_expiration_time};
        # check if token is still valid
  } else {
        return "";       
  }
   my $call = eBay::API::Simple::Trading->new( {
        appid   => 'Webblaze-42c3-402e-9137-46a2dd82f00b',
        devid   => '5ffcc3cf-3652-4b56-aafb-5e89d1cf9a56',
        certid  => 'b9327d52-2328-48e8-bb2b-bd85f29eb985',
        token   => $auth_token,
   } );
                
   $call->execute( 'GetItem', {
        UserID                  => $username,
        ItemID		        => $itemID,
	DetailLevel		=> "ReturnAll"
     });
                  
   if ( $call->has_error() ) {
        print "Call Failed: " . $call->errors_as_string();
   }
                               
  # getters for the response DOM or Hash
  my $dom  = $call->response_dom(); 
  my $hash = $call->response_hash();

  # PictureDetails
  my @pictureDetails         = $dom->findnodes(
  	'//PictureDetails'
  );
  if(@pictureDetails) {
  	return $pictureDetails[0]->findvalue('GalleryURL/text()');
  }
  return "";
}

###
#
# Setup Auction Form
# http://developer.ebay.com/DevZone/XML/docs/WebHelp/GettingTokens-.html
#
###
sub setup_account {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;
  my $sessionID;
  my $timestamp;
  my $username;

  # get eBay Session ID
  my $call = eBay::API::Simple::Auth->new( {
    appid   => 'Webblaze-42c3-402e-9137-46a2dd82f00b',
    devid   => '5ffcc3cf-3652-4b56-aafb-5e89d1cf9a56',
    certid  => 'b9327d52-2328-48e8-bb2b-bd85f29eb985',
  } );

  $call->execute( 'GetSessionID', { RuName => 'Webblazer-Webblaze-42c3-4-zzmyrwad' } );
  if ( $call->has_error() ) {
     die "Call Failed:" . $call->errors_as_string();
  }

  # getters for the response DOM or Hash
  my $dom  = $call->response_dom();
  my $hash = $call->response_hash();

  my @nodes = $dom->findnodes(
    '//GetSessionIDResponse'
  );

  foreach my $n ( @nodes ) {
    $sessionID =  $n->findvalue('SessionID/text()');
    $timestamp =  $n->findvalue('Timestamp/text()');
  }

  # for now only one account per installation
  my $account = SL::AuctionAccount->retrieve('id' => 0);
  
  my $auth_token;
  my $hard_expiration_time; 
  if($account) {
        # get data
     	print $account;
	$username = $account->{username};
        $auth_token = $account->{auth_token};
        $hard_expiration_time = $account->{hard_expiration_time};
  }
  if(!$auth_token) {
	$auth_token = $locale->text('No valid Authentication Token');
  }
  $form->{title} = $locale->text('Setup Auctions');
  $form->header();
  print $form->parse_html_template("auction/setup_auctions", { "TITLE" => $form->{title}, "SESSION_ID" => $sessionID, "TIMESTAMP" => $timestamp, "USERNAME" => $username, "AUTH_TOKEN" => $auth_token, "HARD_EXPIRATION_TIME" => $hard_expiration_time  } );

  $main::lxdebug->leave_sub();
}

###
#
# Dispatcher 
# check which action was selected in the setup form
#
###
sub dispatcher {
  my $form = $main::form;
  
  foreach my $action (qw(save_account authorize_account fetch_auth_token)) {
    if ($form->{"action_${action}"}) {
      call_sub($action);
      return;
    }
  }

  $form->error($main::locale->text('No action defined.'));
}  

sub save_account {
  # save account in DB
  # for now just bind one account to id 0
  my $form    = $main::form;
  my $account = $form->{account} && (ref $form->{account} eq 'HASH') ? $form->{account} : { };
  $account->{ 'id' } = 0;
  my $id = SL::AuctionAccount->save(%{ $account });
  
  # open the setup account form
  call_sub("setup_account");
  return;
}

sub authorize_account {
  my $form 	= $main::form;
  my $locale   	= $main::locale;
  my $sessionID	= $form->{"session_id"};

  $form->{title} = $locale->text('Fetch Token');
  $form->header();
  print $form->parse_html_template("auction/fetch_auth_token", { "TITLE" => $form->{title}, "SESSION_ID" => $sessionID });
} 

sub fetch_auth_token {
  # save token in DB
  # for now just bind one account to id 0
  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;
  my $sessionID = $form->{"session_id"};
  my $timestamp;
  my $eBayAuthToken;  
  my $hardExpirationTime; 

  # get eBay Authentication Token
  my $call = eBay::API::Simple::Auth->new( {
    appid   => 'Webblaze-42c3-402e-9137-46a2dd82f00b',
    devid   => '5ffcc3cf-3652-4b56-aafb-5e89d1cf9a56',
    certid  => 'b9327d52-2328-48e8-bb2b-bd85f29eb985',
  } );

  $call->execute( 'FetchToken', { RuName => 'Webblazer-Webblaze-42c3-4-zzmyrwad', SessionID => $sessionID } );
  if ( $call->has_error() ) {
      	print "Call Failed:" . $call->errors_as_string();
	die "Call Failed:" . $call->errors_as_string();    
  }

  # getters for the response DOM or Hash
  my $dom  = $call->response_dom();
  my $hash = $call->response_hash();

  my @nodes = $dom->findnodes(
    '//FetchTokenResponse'
  );

  foreach my $n ( @nodes ) {
    $timestamp =  $n->findvalue('Timestamp/text()');
    $eBayAuthToken =  $n->findvalue('eBayAuthToken/text()');
    $hardExpirationTime =  $n->findvalue('HardExpirationTime/text()');
  }
  my $account = SL::AuctionAccount->retrieve('id' => 0);
  $account->{ 'auth_token' } = $eBayAuthToken;
  $account->{ 'hard_expiration_time' } = $hardExpirationTime;
  my $id = SL::AuctionAccount->save(%{ $account });

  # open the setup account form
  call_sub("setup_account");
  return;
} 

# Perl trim function to remove whitespace from the start and end of the string
sub trim($)
{
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}

1;
  
__END__
  
=head1 NAME
  
bin/mozilla/auction.pl - Auction frontend.

=head1 FUNCTIONS

=over 4

=item new_item

call new item dialogue from warehouse masks.

PARAMS:
  action  => name of sub to be called when new item is done

=back

=cut
