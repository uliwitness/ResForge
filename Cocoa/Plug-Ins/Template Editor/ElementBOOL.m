#import "ElementBOOL.h"
#import "TemplateWindowController.h"

@implementation ElementBOOL

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn
{
    NSRect frame = NSMakeRect(0, 0, [tableColumn width], 18);
    NSView *view = [[NSView alloc] initWithFrame:frame];
    
    frame.size.width = 60;
    NSButton *on = [[NSButton alloc] initWithFrame:frame];
    on.buttonType = NSRadioButton;
    on.title = @"True";
    on.action = @selector(itemValueUpdated:);
    [on bind:@"value" toObject:self withKeyPath:@"boolValue" options:nil];
    [view addSubview:on];
    
    frame.origin.x += frame.size.width;
    NSButton *off = [[NSButton alloc] initWithFrame:frame];
    off.buttonType = NSRadioButton;
    off.title = @"False";
    off.action = @selector(itemValueUpdated:);
    [off bind:@"value" toObject:self withKeyPath:@"boolValue" options:@{NSValueTransformerNameBindingOption: NSNegateBooleanTransformerName}];
    [view addSubview:off];
    
    return view;
}

- (BOOL)boolValue
{
    return self.value >= 256;
}

- (void)setBoolValue:(BOOL)boolValue
{
    self.value = boolValue ? 256 : 0;
}

@end