//
//  OTRBuddyListViewController.m
//  Off the Record
//
//  Created by Chris Ballinger on 8/11/11.
//  Copyright (c) 2011 Chris Ballinger. All rights reserved.
//
//  This file is part of ChatSecure.
//
//  ChatSecure is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  ChatSecure is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with ChatSecure.  If not, see <http://www.gnu.org/licenses/>.

#import "OTRBuddyListViewController.h"
#import "OTRChatViewController.h"
#import "OTRLoginViewController.h"
#import "OTRXMPPManager.h"
#import "OTRBuddyList.h"
#import "Strings.h"
#import "OTRConstants.h"
#import "OTRAppDelegate.h"
#import "OTRSettingsViewController.h"
#import "OTRDatabaseUtils.h"
#import "OTRManagedStatus.h"
#import "OTRManagedGroup.h"
#import <QuartzCore/QuartzCore.h>

//#define kSignoffTime 500

#define RECENTS_SECTION_INDEX 0
#define BUDDIES_SECTION_INDEX 1

@interface OTRBuddyListViewController(Private)
- (void) selectActiveConversation;
- (void) deleteBuddy:(OTRManagedBuddy*)buddy;
@end

@implementation OTRBuddyListViewController
@synthesize buddyListTableView;
@synthesize chatViewController;
@synthesize protocolManager;
@synthesize selectedBuddy;
@synthesize searchDisplayController;
@synthesize groupManager;

- (void) dealloc {
    self.protocolManager = nil;
    self.buddyListTableView = nil;
    self.chatViewController = nil;
    self.protocolManager = nil;
    self.selectedBuddy = nil;
    _buddyFetchedResultsController = nil;
    _recentBuddiesFetchedResultsController = nil;
    _searchBuddyFetchedResultsController = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (id)init {
    if (self = [super init]) {
        self.title = BUDDY_LIST_STRING;
        self.protocolManager = [OTRProtocolManager sharedInstance];
    }
    return self;
}

- (void)didReceiveMemoryWarning
{
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc that aren't in use.
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    
    [self setupBuddyFetchedResultsControllers];
    
    self.buddyListTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    buddyListTableView.dataSource = self;
    buddyListTableView.delegate = self;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"14-gear.png"] style:UIBarButtonItemStyleBordered target:self action:@selector(showSettingsView:)];
    [self.view addSubview:buddyListTableView];
    
    UISearchBar * searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.buddyListTableView.frame.size.width, 44)];
    //searchBar.delegate = self;
    self.buddyListTableView.tableHeaderView = searchBar;
    
    searchDisplayController = [[UISearchDisplayController alloc] initWithSearchBar:searchBar contentsController:self];
    
    searchDisplayController.delegate = self;
    searchDisplayController.searchResultsDataSource = self;
    searchDisplayController.searchResultsDelegate = self;
    
    //[buddyListTableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0] atScrollPosition:UITableViewScrollPositionTop animated:NO];
    
    self.buddyListTableView.contentOffset = CGPointMake(0, self.searchDisplayController.searchBar.frame.size.height);

    
    [self updateTitleWithUnreadCount:[[self.unreadMessagesFetchedResultsContrller sections][0] numberOfObjects]];
    // uncomment to see a LOT of console output
	// [Debug setDebuggingEnabled:YES];
	NSLog(@"LibOrange (v: %@): -beginTest\n", @lib_orange_version_string);
}

-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    buddyListTableView.frame = self.view.bounds;
    buddyListTableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleRightMargin;
    [buddyListTableView reloadData];
}


-(void)viewDidAppear:(BOOL)animated {
    [self.buddyListTableView reloadData];
    [super viewDidAppear:animated];
}

- (void) showSettingsView:(id)sender {
    [self.navigationController pushViewController:[OTR_APP_DELEGATE settingsViewController] animated:YES];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    self.buddyListTableView = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    // Return YES for supported orientations
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        return YES;
    } else {
        return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
    }
}

-(void)setupBuddyFetchedResultsControllers
{
    groupManager = [[OTRBuddyListGroupManager alloc] initWithFetchedResultsDelegete:self];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if ([tableView isEqual:self.buddyListTableView]) {
        //+2 one for recent conversations the other for offline buddies
        NSUInteger num = [self.groupManager numberOfGroups]+2;
        return num;
    }
    return 1;
}

- (NSString*)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if ([tableView isEqual:self.buddyListTableView]) {
        if (section == RECENTS_SECTION_INDEX) {
            return RECENT_STRING;
        } else if ([self.groupManager numberOfGroups] >= section) {
            return [self.groupManager groupNameAtIndex:section-1];
        }
        else
        {
            return @"Offline";
        }
    }
    return @"";
}


- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)sectionIndex {
    if ([tableView isEqual:self.buddyListTableView]) {
        if (sectionIndex == RECENTS_SECTION_INDEX) {
            return [[self.recentBuddiesFetchedResultsController sections][sectionIndex] numberOfObjects];
        } else if ([self.groupManager numberOfGroups] >= sectionIndex){
            NSUInteger num =  [self.groupManager numberOfBuddiesAtIndex:sectionIndex-1];
            return num;
        }
        else
        {
            return [[self.offlineBuddiesFetchedResultsController sections][0] numberOfObjects];
        }
        return 0;
    }
    else if ([tableView isEqual:self.searchDisplayController.searchResultsTableView])
    {
        return [[self.searchBuddyFetchedResultsController sections][sectionIndex] numberOfObjects];
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
	if (cell == nil)
	{
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Cell"];
	}
    
    OTRManagedBuddy *buddy = nil;
    
    if ([tableView isEqual:self.searchDisplayController.searchResultsTableView]) {
        buddy = [self.searchBuddyFetchedResultsController objectAtIndexPath:indexPath];
        [self configureCell:cell withBuddy:buddy];
    }
    else if (indexPath.section == RECENTS_SECTION_INDEX) {
        buddy = [self.recentBuddiesFetchedResultsController objectAtIndexPath:indexPath];
        [self configureRecentCell:cell withBuddy:buddy];
    } else{
        if ([self.groupManager numberOfGroups] >= indexPath.section) {
            buddy = [self.groupManager buddyAtIndexPath:[NSIndexPath indexPathForItem:indexPath.row inSection:indexPath.section-1]];
        }
        else{
            NSFetchedResultsController* resultsController = self.offlineBuddiesFetchedResultsController;
            buddy = [resultsController objectAtIndexPath:[NSIndexPath indexPathForItem:indexPath.row inSection:0]];
            
        }
        [self configureCell:cell withBuddy:buddy];
        
       
        //OTRManagedGroup * managedGroup = [self.groupFetchedResultsController objectAtIndexPath:[NSIndexPath indexPathForItem:indexPath.row inSection:0]];
        
        //cell.textLabel.text = [NSString stringWithFormat:@"%d",indexPath.row];
        //cell.textLabel.text = [NSString stringWithFormat:@"Num buddies: %d in: %@",managedGroup.buddies.count,managedGroup.name];
    }
    
    
    
    
    return cell;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == RECENTS_SECTION_INDEX) {
        return UITableViewCellEditingStyleDelete;
    } else{
        return UITableViewCellEditingStyleNone;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    OTRManagedBuddy * managedBuddy = nil;
    if ([tableView isEqual:self.searchDisplayController.searchResultsTableView]) {
        [self.searchDisplayController   setActive:NO];
        managedBuddy = [self.searchBuddyFetchedResultsController objectAtIndexPath:indexPath];
        [self enterConversationWithBuddy:managedBuddy];
    }
    
    if ([tableView isEqual:self.buddyListTableView]) {
        
        if (indexPath.section == RECENTS_SECTION_INDEX) {
            managedBuddy = [self.recentBuddiesFetchedResultsController objectAtIndexPath:indexPath];
            
        }
        else{
            if ([self.groupManager numberOfGroups] >= indexPath.section) {
                managedBuddy = [self.groupManager buddyAtIndexPath:[NSIndexPath indexPathForItem:indexPath.row inSection:indexPath.section-1]];
            }
            else{
                NSFetchedResultsController* resultsController = self.offlineBuddiesFetchedResultsController;
                managedBuddy = [resultsController objectAtIndexPath:[NSIndexPath indexPathForItem:indexPath.row inSection:0]];
            }
        }
    }
    
    if (managedBuddy) {
        [self enterConversationWithBuddy:managedBuddy];
    }
    

    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
    }
}

- (void) tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == RECENTS_SECTION_INDEX && editingStyle == UITableViewCellEditingStyleDelete) {
        [[self.recentBuddiesFetchedResultsController objectAtIndexPath:indexPath] deleteAllMessages];
    }
}

- (void) deleteBuddy:(OTRManagedBuddy*)buddy {
    //TODO best way to delete buddy
    //[[[[OTRProtocolManager sharedInstance] buddyList] activeConversations] removeObject:buddy];
}

-(void)enterConversationWithBuddy:(OTRManagedBuddy*)buddy
{
    if(!buddy) {
        return;
    }
    self.selectedBuddy = buddy;
    chatViewController.buddy = buddy;
    
    BOOL chatViewIsVisible = chatViewController.isViewLoaded && chatViewController.view.window;
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone && !chatViewIsVisible && self.navigationController.visibleViewController != chatViewController) {
        [self.navigationController setViewControllers:[NSArray arrayWithObjects:self, chatViewController, nil] animated:YES];
    }
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if(buttonIndex == 1) // Reply
    {
        //[self enterConversationWithBuddy:buddy];
    }
}

#pragma mark - NSFetchedReusltsControllerDelegate
    
-(NSFetchedResultsController *)buddyFetchedResultsController{
    if (_buddyFetchedResultsController)
    {
        return _buddyFetchedResultsController;
    }
    
    NSPredicate * buddyFilter = [NSPredicate predicateWithFormat:@"accountName != nil OR displayName != nil"];
    
    _buddyFetchedResultsController = [OTRManagedBuddy MR_fetchAllGroupedBy:nil withPredicate:buddyFilter sortedBy:@"currentStatus,displayName" ascending:YES delegate:self];
    
    return _buddyFetchedResultsController;
}

-(NSFetchedResultsController *)searchBuddyFetchedResultsController
{
    if (_searchBuddyFetchedResultsController)
    {
        return _searchBuddyFetchedResultsController;
    }
    
    NSPredicate * buddyFilter = [NSPredicate predicateWithFormat:@"accountName != nil OR displayName != nil"];
    _searchBuddyFetchedResultsController = [OTRManagedBuddy MR_fetchAllGroupedBy:nil withPredicate:buddyFilter sortedBy:@"currentStatus,displayName" ascending:YES delegate:self];
    
    return _searchBuddyFetchedResultsController;
    
}

-(NSFetchedResultsController *)recentBuddiesFetchedResultsController
{
    if(_recentBuddiesFetchedResultsController)
    {
        return _recentBuddiesFetchedResultsController;
    }
    
    NSPredicate * predicate = [NSPredicate predicateWithFormat:@"messages.@count != 0"];
    NSPredicate * buddyFilter = [NSPredicate predicateWithFormat:@"accountName != nil OR displayName != nil"];
    NSPredicate * compoundPredicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[predicate,buddyFilter]];
    
    _recentBuddiesFetchedResultsController = [OTRManagedBuddy MR_fetchAllSortedBy:@"lastMessageDate" ascending:NO withPredicate:compoundPredicate groupBy:nil delegate:self];
 
    return _recentBuddiesFetchedResultsController;
}

-(NSFetchedResultsController *)unreadMessagesFetchedResultsContrller
{
    if(_unreadMessagesFetchedResultsContrller)
    {
        return _unreadMessagesFetchedResultsContrller;
    }
    
    NSPredicate * encryptionFilter = [NSPredicate predicateWithFormat:@"self.isEncrypted == NO"];
    NSPredicate * unreadFilter = [NSPredicate predicateWithFormat:@"isRead == NO"];
    NSPredicate * unreadMessagePredicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[encryptionFilter, unreadFilter]];
    
    _unreadMessagesFetchedResultsContrller = [OTRManagedMessage MR_fetchAllGroupedBy:nil withPredicate:unreadMessagePredicate sortedBy:nil ascending:YES delegate:self];
    
    return _unreadMessagesFetchedResultsContrller;
}

-(NSFetchedResultsController *) offlineBuddiesFetchedResultsController
{
    if(_offlineBuddiesFetchedResultsController)
    {
        return _offlineBuddiesFetchedResultsController;
    }
    
    NSPredicate * offlineBuddyFilter = [NSPredicate predicateWithFormat:@"%K == %d",OTRManagedBuddyAttributes.currentStatus,kOTRBuddyStatusOffline];
    
    NSString * sortByString = [NSString stringWithFormat:@"%@,%@",OTRManagedBuddyAttributes.displayName,OTRManagedBuddyAttributes.accountName];
    
    _offlineBuddiesFetchedResultsController = [OTRManagedBuddy MR_fetchAllGroupedBy:nil withPredicate:offlineBuddyFilter sortedBy:sortByString ascending:YES delegate:self];
    
    return _offlineBuddiesFetchedResultsController;
}

- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller {
    
    UITableView * tableView = nil;
    
    if([controller isEqual:_searchBuddyFetchedResultsController])
    {
        tableView = self.searchDisplayController.searchResultsTableView;
    }
    
    [tableView beginUpdates];
    
}

- (void)controller:(NSFetchedResultsController *)controller didChangeObject:(id)anObject
       atIndexPath:(NSIndexPath *)indexPath forChangeType:(NSFetchedResultsChangeType)type
      newIndexPath:(NSIndexPath *)newIndexPath {
    
    UITableView *tableView = nil;
    OTRManagedBuddy * buddy = anObject;
    NSIndexPath * modifiedIndexPath = indexPath;
    NSIndexPath * modifiedNewIndexPath = newIndexPath;
    
    BOOL isRecentBuddiesFetchedResultsController = [controller isEqual:_recentBuddiesFetchedResultsController];
    
    if ([self.groupManager.buddyFetchedResultsControllerArray containsObject:controller]) {
        tableView = self.buddyListTableView;
        NSInteger section = [self.groupManager.buddyFetchedResultsControllerArray indexOfObject:controller]+1;
        modifiedNewIndexPath = [NSIndexPath indexPathForRow:newIndexPath.row inSection:section];
        modifiedIndexPath = [NSIndexPath indexPathForRow:indexPath.row inSection:section];
    }
    else if (isRecentBuddiesFetchedResultsController)
    {
        tableView = self.buddyListTableView;
    }
    else if([controller isEqual:_searchBuddyFetchedResultsController])
    {
        tableView = self.searchDisplayController.searchResultsTableView;
    }
    else if([controller isEqual:_unreadMessagesFetchedResultsContrller])
    {
        [self updateTitleWithUnreadCount:[[controller sections][indexPath.section] numberOfObjects]];
    }
    else if([controller isEqual:_offlineBuddiesFetchedResultsController])
    {
        tableView = self.buddyListTableView;
        NSInteger section = tableView.numberOfSections-1;
        modifiedNewIndexPath = [NSIndexPath indexPathForRow:newIndexPath.row inSection:section];
        modifiedIndexPath = [NSIndexPath indexPathForRow:indexPath.row inSection:section];
    }
    
    if (tableView) {
        switch (type) {
            case NSFetchedResultsChangeInsert:
                [tableView insertRowsAtIndexPaths:@[modifiedNewIndexPath] withRowAnimation:UITableViewRowAnimationFade];
                break;
            case NSFetchedResultsChangeDelete:
                [tableView deleteRowsAtIndexPaths:@[modifiedIndexPath] withRowAnimation:UITableViewRowAnimationFade];
                break;
                
            case NSFetchedResultsChangeUpdate:
                if ([controller isEqual:_recentBuddiesFetchedResultsController]) {
                    [self configureRecentCell:[tableView cellForRowAtIndexPath:modifiedIndexPath] withBuddy:buddy];
                }
                else{
                    [self configureCell:[tableView cellForRowAtIndexPath:modifiedIndexPath] withBuddy:buddy];
                }
                break;
                
            case NSFetchedResultsChangeMove:
                if ([controller isEqual:_recentBuddiesFetchedResultsController]) {
                    [self configureRecentCell:[tableView cellForRowAtIndexPath:modifiedIndexPath] withBuddy:buddy];
                }
                else{
                    [self configureCell:[tableView cellForRowAtIndexPath:modifiedIndexPath] withBuddy:buddy];
                }
                [tableView moveRowAtIndexPath:modifiedIndexPath toIndexPath:modifiedNewIndexPath];
                break;
        }
    }
}

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller {
    UITableView * tableView = nil;
    
    if([controller isEqual:_searchBuddyFetchedResultsController])
    {
        tableView = self.searchDisplayController.searchResultsTableView;
    }
    
    [tableView endUpdates];
    
}

-(void)manager:(OTRBuddyListGroupManager *)manager didChangeSectionAtIndex:(NSUInteger)section newSectionIndex:(NSUInteger)newSection forChangeType:(NSFetchedResultsChangeType)type
{
    [self.buddyListTableView beginUpdates];
    switch (type) {
        case NSFetchedResultsChangeInsert:
            [self.buddyListTableView insertSections:[NSIndexSet indexSetWithIndex:newSection+1] withRowAnimation:UITableViewRowAnimationAutomatic];
            break;
        case NSFetchedResultsChangeUpdate:
            [self.buddyListTableView reloadSections:[NSIndexSet indexSetWithIndex:newSection+1] withRowAnimation:UITableViewRowAnimationNone];
            break;
        case NSFetchedResultsChangeMove:
            [self.buddyListTableView moveSection:section+1 toSection:newSection+1];
            break;
        case NSFetchedResultsChangeDelete:
            [self.buddyListTableView deleteSections:[NSIndexSet indexSetWithIndex:section+1] withRowAnimation:UITableViewRowAnimationAutomatic];
            break;
            
        default:
            break;
    }
    [self.buddyListTableView endUpdates];
}

-(void)updateTitleWithUnreadCount:(NSInteger) unreadMessagesCount
{
    NSMutableString * title = [BUDDY_LIST_STRING mutableCopy];
    if (unreadMessagesCount > 0) {
        if (unreadMessagesCount < 100) {
            [title appendFormat:@" (%d)",unreadMessagesCount];
        }
        else{
            [title appendFormat:@" (99+)"];
        }
    }
    
    self.title = title;
}


-(void) configureRecentCell:(UITableViewCell *)cell withBuddy:(OTRManagedBuddy *) buddy
{
    [self configureCell:cell withBuddy:buddy];
    NSInteger numberOfUnreadMessages = [buddy numberOfUnreadMessages];
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd h:mm"];
    
    formatter.timeZone = [NSTimeZone localTimeZone];
    
    NSString *stringFromDate = [formatter stringFromDate:buddy.lastMessageDate];
    
    
    cell.detailTextLabel.text = stringFromDate;
    
    if (numberOfUnreadMessages>0) {
        UILabel * messageCountLabel = nil;
        if (cell.accessoryView) {
            messageCountLabel = (UILabel *)cell.accessoryView;
        }
        else
        {
            messageCountLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 42.0, 28.0)];
            messageCountLabel.backgroundColor = [UIColor darkGrayColor];
            messageCountLabel.textColor = [UIColor whiteColor];
            messageCountLabel.layer.cornerRadius = 14;
            messageCountLabel.numberOfLines = 0;
            messageCountLabel.lineBreakMode = NSLineBreakByWordWrapping;
            messageCountLabel.textAlignment = UITextAlignmentCenter;
        }
        if (numberOfUnreadMessages > 99) {
            messageCountLabel.text = [NSString stringWithFormat:@"%d+",99];
        }
        else
        {
            messageCountLabel.text = [NSString stringWithFormat:@"%d",[buddy numberOfUnreadMessages]];
        }
        cell.accessoryView = messageCountLabel;
    }
    else
    {
        cell.accessoryView=nil;
    }
}

-(void) configureCell:(UITableViewCell *)cell withBuddy:(OTRManagedBuddy *)buddy
{
    NSString *buddyUsername = buddy.displayName;
    if (![buddy.displayName length]) {
        buddyUsername = buddy.accountName;
    }
    
    OTRBuddyStatus buddyStatus = [buddy currentStatusMessage].statusValue;
    
    cell.textLabel.text = buddyUsername;
    
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.detailTextLabel.textColor = [UIColor lightGrayColor];
    cell.detailTextLabel.text = [buddy currentStatusMessage].message;
    
    switch(buddyStatus)
    {
        case kOTRBuddyStatusOffline:
            cell.textLabel.textColor = [UIColor lightGrayColor];
            cell.imageView.image = [UIImage imageNamed:@"offline.png"];
            break;
        case kOTRBuddyStatusAway:
            cell.textLabel.textColor = [UIColor darkGrayColor];
            cell.imageView.image = [UIImage imageNamed:@"idle.png"];
            break;
        case kOTRBuddyStatusXa:
            cell.textLabel.textColor = [UIColor darkGrayColor];
            cell.imageView.image = [UIImage imageNamed:@"away.png"];
            break;
        case kOTRBUddyStatusDnd:
            cell.textLabel.textColor = [UIColor darkGrayColor];
            cell.imageView.image = [UIImage imageNamed:@"away.png"];
            break;
        case kOTRBuddyStatusAvailable:
            cell.textLabel.textColor = [UIColor darkTextColor];
            cell.imageView.image = [UIImage imageNamed:@"available.png"];
            break;
        default:
            cell.textLabel.textColor = [UIColor lightGrayColor];
            cell.imageView.image = [UIImage imageNamed:@"offline.png"];
    }
}



- (void)filterContentForSearchText:(NSString*)searchText scope:(NSString*)scope
{
    NSFetchRequest * searchRequest = [[self searchBuddyFetchedResultsController] fetchRequest];
    
    NSPredicate * buddyFilter = [NSPredicate predicateWithFormat:@"accountName contains[cd] %@ OR displayName contains[cd] %@",searchText ,searchText];
    
    [searchRequest setPredicate:buddyFilter];
    
    NSError *error = nil;
    if (![[self searchBuddyFetchedResultsController] performFetch:&error]) {
        // Handle error
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        abort();
    }
}

- (BOOL)searchDisplayController:(UISearchDisplayController *)controller shouldReloadTableForSearchString:(NSString *)searchString
{
    if([searchString length])
    {
        [self filterContentForSearchText:searchString scope:nil];
        return YES;
    }
}
-(BOOL)searchDisplayController:(UISearchDisplayController *)controller shouldReloadTableForSearchScope:(NSInteger)searchOption
{
    return YES;
}

-(void)searchDisplayController:(UISearchDisplayController *)controller willHideSearchResultsTableView:(UITableView *)tableView
{
    self.searchBuddyFetchedResultsController.delegate = nil;
    self.searchBuddyFetchedResultsController = nil;
}

@end
