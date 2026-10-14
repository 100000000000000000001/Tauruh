#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "Navbar.h"
#import "Shared/Navigation/Links.h"
#import "Shared/Navigation/AddTabSheet.h"

static NSArray<NSDictionary *> *tabPresets(void) {
    return @[
        @{SGRNavbarTitle: @"Home", SGRNavbarURI: @"spotify:home", SGRNavbarIcon: @"home"},
        @{SGRNavbarTitle: @"Search", SGRNavbarURI: @"spotify:search", SGRNavbarIcon: @"search"},
        @{SGRNavbarTitle: @"Your Library", SGRNavbarURI: @"spotify:collection", SGRNavbarIcon: @"collection"},
        @{SGRNavbarTitle: @"Liked Songs", SGRNavbarURI: @"spotify:collection:tracks", SGRNavbarIcon: @"heart"},
        @{SGRNavbarTitle: @"Playlists", SGRNavbarURI: @"spotify:playlists", SGRNavbarIcon: @"playlist"},
        @{SGRNavbarTitle: @"Albums", SGRNavbarURI: @"spotify:collection:albums", SGRNavbarIcon: @"album"},
        @{SGRNavbarTitle: @"Artists", SGRNavbarURI: @"spotify:collection:artists", SGRNavbarIcon: @"artist"},
        @{SGRNavbarTitle: @"Podcasts", SGRNavbarURI: @"spotify:collection:podcasts", SGRNavbarIcon: @"podcasts"},
        @{SGRNavbarTitle: @"Audiobooks", SGRNavbarURI: @"spotify:collection:audiobooks", SGRNavbarIcon: @"audiobook"},
        @{SGRNavbarTitle: @"Downloads", SGRNavbarURI: @"spotify:collection:downloads", SGRNavbarIcon: @"downloaded"},
        @{SGRNavbarTitle: @"Your Episodes", SGRNavbarURI: @"spotify:collection:your-episodes", SGRNavbarIcon: @"bookmark"},
        @{SGRNavbarTitle: @"Browse", SGRNavbarURI: @"spotify:browse", SGRNavbarIcon: @"browse"},
        @{SGRNavbarTitle: @"New Releases", SGRNavbarURI: @"spotify:new-releases", SGRNavbarIcon: @"star"},
        @{SGRNavbarTitle: @"Made For You", SGRNavbarURI: @"spotify:made-for-you", SGRNavbarIcon: @"user"},
        @{SGRNavbarTitle: @"Concerts", SGRNavbarURI: @"spotify:concerts", SGRNavbarIcon: @"events"},
        @{SGRNavbarTitle: @"Queue", SGRNavbarURI: @"spotify:now-playing:queue", SGRNavbarIcon: @"queue"},
        @{SGRNavbarTitle: @"Create", SGRNavbarURI: @"spotify:create-menu", SGRNavbarIcon: @"plus"},
    ];
}

static NSMutableArray<NSMutableDictionary *> *navbarEntries(void) {
    NSArray<NSString *> *stock = SGRNavbarStock();
    NSMutableArray<NSMutableDictionary *> *entries = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSDictionary *entry in SGRNavbarLayout()) {
        NSString *ident = entry[SGRNavbarID];
        if (![ident isKindOfClass:NSString.class] || [seen containsObject:ident]) continue;
        if (!entry[SGRNavbarURI] && ![stock containsObject:ident]) continue;
        [seen addObject:ident];
        [entries addObject:[entry mutableCopy]];
    }
    for (NSString *ident in stock) {
        if ([seen containsObject:ident]) continue;
        [entries addObject:[@{SGRNavbarID: ident, SGRNavbarTitle: ident} mutableCopy]];
    }
    return entries;
}

static void appendTab(NSDictionary *tab) {
    NSMutableDictionary *entry = [@{SGRNavbarID: NSUUID.UUID.UUIDString,
                                    SGRNavbarTitle: tab[SGTabTitle] ?: tab[SGTabURI],
                                    SGRNavbarURI: tab[SGTabURI],
                                    SGRNavbarIcon: tab[SGTabIcon] ?: @"star"} mutableCopy];
    if (tab[SGTabIconSet]) entry[SGRNavbarIconSet] = tab[SGTabIconSet];
    SGRSetNavbarLayout([navbarEntries() arrayByAddingObject:entry]);
    SGRRefreshTabBar();
}

typedef NS_ENUM(NSInteger, SGRNavbarSection) {
    SGRNavbarSectionSwitch,
    SGRNavbarSectionTabs,
    SGRNavbarSectionAdd,
    SGRNavbarSectionReset,
    SGRNavbarSectionCount,
};

@interface SGRNavbarPage : SGPage
@end

@implementation SGRNavbarPage {
    NSMutableArray<NSMutableDictionary *> *_entries;
    UIView *_intro;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"Navbar";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.allowsSelectionDuringEditing = YES;
    self.tableView.editing = YES;
    _intro = SGNote(@"Drag to reorder. Tap a tab to change its name or icon; use its switch to show or hide it.");
    self.tableView.tableHeaderView = _intro;
    _entries = navbarEntries();
}

// The Add page writes straight to the layout, so the list is read again on the way back.
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _entries = navbarEntries();
    [self.tableView reloadData];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    SGFitNote(self.tableView, _intro, 24, 0);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (void)save {
    SGRSetNavbarLayout(_entries);
    SGRRefreshTabBar();
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return SGRNavbarSectionCount;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    if (section == SGRNavbarSectionSwitch) return 5;
    return section == SGRNavbarSectionTabs ? (NSInteger)_entries.count : 1;
}

- (NSString *)headerFor:(NSInteger)section {
    return section == SGRNavbarSectionTabs ? @"Tabs" : nil;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    NSString *title = [self headerFor:section];
    return title ? SGSectionHeader(table, title) : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    if ([self headerFor:section]) return SGSectionHeaderHeight;
    return [self tableView:table numberOfRowsInSection:section] ? SGSectionGap : CGFLOAT_MIN;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"navbar");
    switch (path.section) {
        case SGRNavbarSectionSwitch: {
            BOOL labels = path.row == 1, profile = path.row == 2, compact = path.row == 3, appleIcons = path.row == 4;
            NSString *title = appleIcons ? @"Apple Music tab icons"
                : profile ? @"Show profile photo" : compact ? @"Compact player and tabs"
                : labels ? @"Hide labels" : @"Custom navbar";
            NSString *detail = appleIcons ? @"Use Apple's style for built-in tabs"
                : profile ? @"Open Spotify's side menu" : compact ? @"Share one row while scrolling"
                : labels ? @"Icons only" : nil;
            SGFillCell(cell, title, detail, nil, nil);
            UISwitch *toggle = [UISwitch new];
            toggle.onTintColor = SGGreen();
            toggle.tag = path.row;
            toggle.on = profile ? SGFlag(SGRKeyNavbarProfilePhoto, YES)
                                : compact ? SGFlag(SGRKeyNavbarCompact, YES)
                                : appleIcons ? SGFlag(SGRKeyNavbarAppleIcons, NO)
                                : labels ? SGFlag(SGRKeyNavbarHideLabels, YES) : SGEnabled(SGRKeyNavbar);
            [toggle addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
            break;
        }
        case SGRNavbarSectionTabs: {
            NSDictionary *entry = _entries[(NSUInteger)path.row];
            BOOL hidden = [entry[SGRNavbarHidden] boolValue];
            NSString *uri = entry[SGRNavbarURI];
            NSString *detail = uri ?: (entry[SGRNavbarIcon] != nil
                || ![entry[SGRNavbarTitle] isEqualToString:entry[SGRNavbarID]]
                ? @"Spotify tab · Tap to customize" : @"Spotify's own tab");
            SGFillCell(cell, entry[SGRNavbarTitle], detail, hidden ? SGGrey() : nil, nil);
            UISwitch *toggle = [UISwitch new];
            toggle.onTintColor = SGGreen();
            toggle.on = !hidden;
            toggle.tag = path.row;
            [toggle addTarget:self action:@selector(visibilityToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        }
        case SGRNavbarSectionAdd:
            SGFillCell(cell, @"Add a tab…", nil, nil, @"plus");
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        default:
            SGFillCell(cell, @"Use Spotify's order", nil, nil, @"arrow.uturn.backward");
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
    }
    return cell;
}

- (BOOL)tableView:(UITableView *)table canMoveRowAtIndexPath:(NSIndexPath *)path {
    return path.section == SGRNavbarSectionTabs;
}

- (BOOL)tableView:(UITableView *)table canEditRowAtIndexPath:(NSIndexPath *)path {
    return path.section == SGRNavbarSectionTabs;
}

// Spotify's own tabs stay on the list to be switched back on; only the mod's own can go.
- (UITableViewCellEditingStyle)tableView:(UITableView *)table editingStyleForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section != SGRNavbarSectionTabs) return UITableViewCellEditingStyleNone;
    return _entries[(NSUInteger)path.row][SGRNavbarURI] ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (NSIndexPath *)tableView:(UITableView *)table targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)from toProposedIndexPath:(NSIndexPath *)to {
    return to.section == SGRNavbarSectionTabs ? to : from;
}

- (void)tableView:(UITableView *)table moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    NSMutableDictionary *entry = _entries[(NSUInteger)from.row];
    [_entries removeObjectAtIndex:(NSUInteger)from.row];
    [_entries insertObject:entry atIndex:(NSUInteger)to.row];
    [self save];
}

- (void)tableView:(UITableView *)table commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if (style != UITableViewCellEditingStyleDelete) return;
    [_entries removeObjectAtIndex:(NSUInteger)path.row];
    [self save];
    [table deleteRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section == SGRNavbarSectionTabs) {
        [self editRow:path.row];
    } else if (path.section == SGRNavbarSectionAdd) {
        __weak typeof(self) weakSelf = self;
        SGPresentAddTabSheet(self, tabPresets(), ^(NSDictionary *tab) {
            appendTab(tab);
            SGRNavbarPage *page = weakSelf;
            if (!page) return;
            page->_entries = navbarEntries();
            [page.tableView reloadData];
        });
    } else if (path.section == SGRNavbarSectionReset) {
        [self reset];
    }
}

- (void)visibilityToggled:(UISwitch *)toggle {
    if (toggle.tag < 0 || (NSUInteger)toggle.tag >= _entries.count) return;
    NSMutableDictionary *entry = _entries[(NSUInteger)toggle.tag];
    if (toggle.on) [entry removeObjectForKey:SGRNavbarHidden];
    else entry[SGRNavbarHidden] = @YES;
    [self save];
}

- (void)editRow:(NSInteger)row {
    if (row < 0 || (NSUInteger)row >= _entries.count) return;
    NSMutableDictionary *entry = _entries[(NSUInteger)row];
    NSString *ident = entry[SGRNavbarID];
    if (entry[SGRNavbarURI]) {
        __weak typeof(self) weakSelf = self;
        SGPresentEditTabSheet(self, tabPresets(), entry, ^(NSDictionary *edited) {
            typeof(self) page = weakSelf;
            if (!page) return;
            NSMutableDictionary *current = nil;
            for (NSMutableDictionary *candidate in page->_entries) {
                if ([candidate[SGRNavbarID] isEqualToString:ident]) { current = candidate; break; }
            }
            if (!current) return;
            current[SGRNavbarTitle] = edited[SGTabTitle];
            current[SGRNavbarURI] = edited[SGTabURI];
            current[SGRNavbarIcon] = edited[SGTabIcon];
            if (edited[SGTabIconSet]) current[SGRNavbarIconSet] = edited[SGTabIconSet];
            else [current removeObjectForKey:SGRNavbarIconSet];
            [page save];
            [page.tableView reloadData];
        }, ^{
            typeof(self) page = weakSelf;
            if (!page) return;
            NSUInteger index = [page->_entries indexOfObjectPassingTest:^BOOL(NSDictionary *candidate, NSUInteger idx, BOOL *stop) {
                return [candidate[SGRNavbarID] isEqualToString:ident];
            }];
            if (index == NSNotFound) return;
            [page->_entries removeObjectAtIndex:index];
            [page save];
            [page.tableView reloadData];
        });
        return;
    }

    NSString *title = entry[SGRNavbarTitle] ?: ident;
    NSString *icon = entry[SGRNavbarIcon] ?: @"star";
    for (NSDictionary *preset in tabPresets()) {
        if ([preset[SGRNavbarTitle] isEqualToString:ident]) {
            if (!entry[SGRNavbarIcon]) icon = preset[SGRNavbarIcon];
            break;
        }
    }
    NSMutableDictionary *tab = [@{SGTabTitle: title, SGTabURI: @"spotify:home", SGTabIcon: icon} mutableCopy];
    if (entry[SGRNavbarIconSet]) tab[SGTabIconSet] = entry[SGRNavbarIconSet];
    __weak typeof(self) weakSelf = self;
    SGPresentEditTabAppearanceSheet(self, tab, ^(NSDictionary *edited) {
        typeof(self) page = weakSelf;
        if (!page) return;
        NSMutableDictionary *current = nil;
        for (NSMutableDictionary *candidate in page->_entries) {
            if ([candidate[SGRNavbarID] isEqualToString:ident]) { current = candidate; break; }
        }
        if (!current) return;
        current[SGRNavbarTitle] = edited[SGTabTitle];
        current[SGRNavbarIcon] = edited[SGTabIcon];
        if (edited[SGTabIconSet]) current[SGRNavbarIconSet] = edited[SGTabIconSet];
        else [current removeObjectForKey:SGRNavbarIconSet];
        [page save];
        [page.tableView reloadData];
    });
}

- (void)toggled:(UISwitch *)toggle {
    if (toggle.tag == 2) {
        SGSetEnabled(SGRKeyNavbarProfilePhoto, toggle.on);
        SGRNavbarRefreshProfilePhotos();
    } else if (toggle.tag == 3) {
        SGSetEnabled(SGRKeyNavbarCompact, toggle.on);
        SGRSetTabBarMinimized(SGRTabBarMinimized(), NO);
        SGRRefreshTabBar();
        SGRNowPlayingBarFollowTabBar();
    } else if (toggle.tag == 4) {
        SGSetEnabled(SGRKeyNavbarAppleIcons, toggle.on);
        SGRRefreshTabBar();
    } else {
        SGSetEnabled(toggle.tag == 1 ? SGRKeyNavbarHideLabels : SGRKeyNavbar, toggle.on);
        SGRRefreshTabBar();
    }
}

- (void)reset {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Use Spotify's order"
                                                                  message:@"Every tab of Spotify's comes back where Spotify put it, and the tabs you added go."
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        SGRSetNavbarLayout(@[]);
        SGRRefreshTabBar();
        self->_entries = navbarEntries();
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

UIViewController *SGRNavbarSettingsPage(void) {
    return [SGRNavbarPage new];
}

UIViewController *SGRNavbarEditorPage(void) {
    return [SGRNavbarPage new];
}
