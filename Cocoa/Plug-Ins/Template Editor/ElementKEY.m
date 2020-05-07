#import "ElementKEY.h"
#import "ElementCASE.h"
#import "TemplateWindowController.h"

@implementation ElementKEY

- (instancetype)initForType:(NSString *)t withLabel:(NSString *)l
{
    if (self = [super initForType:t withLabel:l]) {
        self.isKey = [t characterAtIndex:0] == 'K';
        if (self.isKey) self.width = 240;
    }
    return self;
}

- (void)configureView:(NSView *)view
{
    if (!self.isKey) {
        [super configureView:view];
        return;
    }
    NSRect frame = view.frame;
    frame.size.width = self.width-4;
    NSPopUpButton *keySelect = [[NSPopUpButton alloc] initWithFrame:frame];
    if (self.keyedSections.count) {
        keySelect.target = self;
        keySelect.action = @selector(keyChanged:);
    } else {
        keySelect.action = @selector(itemValueUpdated:);
    }
    [keySelect bind:@"content" toObject:self withKeyPath:@"cases" options:nil];
    [keySelect bind:@"selectedObject" toObject:self withKeyPath:@"value" options:@{NSValueTransformerBindingOption:self,
                                                                                   NSValidatesImmediatelyBindingOption:@(self.formatter != nil)}];
    [view addSubview:keySelect];
}

- (IBAction)keyChanged:(NSPopUpButton *)sender
{
    [self setCase:self.cases[sender.indexOfSelectedItem]];
    TemplateWindowController *controller = sender.window.windowController;
    [controller.dataList reloadData];
    [controller itemValueUpdated:sender];
}

- (void)setCase:(ElementCASE *)element
{
    ElementKEYB *newSection = self.keyedSections[element.value];
    if (newSection != self.currentSection) {
        if (!self.observing) {
            // Check if the section sizes match and attempt to copy the data
            UInt32 currentSize = 0;
            [self.currentSection.subElements sizeOnDisk:&currentSize];
            UInt32 newSize = 0;
            [newSection.subElements sizeOnDisk:&newSize];
            if (currentSize == newSize && currentSize > 0) {
                NSMutableData *data = [NSMutableData dataWithLength:currentSize];
                ResourceStream *stream = [ResourceStream streamWithData:data];
                [self.currentSection writeDataTo:stream];
                stream = [ResourceStream streamWithData:data];
                [newSection readDataFrom:stream];
                
            }
        }
        [self.parentList removeElement:self.currentSection];
        self.currentSection = newSection;
        [self.parentList insertElement:self.currentSection after:self];
    }
}

- (void)readCases
{
    self.cases = [NSMutableArray new];
    self.caseMap = [NSMutableDictionary new];
    self.keyedSections = [NSMutableDictionary new];
    __kindof Element *element = [self.parentList peek:1];
    // Read CASEs
    while (element.class == ElementCASE.class) {
        [self.parentList pop];
        [self.cases addObject:element];
        [self.caseMap setObject:element forKey:[element value]];
        element = [self.parentList peek:1];
    }
    // Read KEYBs
    while (element.class == ElementKEYB.class) {
        [self.parentList pop];
        element.parentList = self.parentList;
        [element configure];
        // Allow one KEYB to be used for multiple cases
        NSArray *vals = [element.label componentsSeparatedByString:@","];
        for (NSString *value in vals) {
            ElementCASE *caseEl = self.caseMap[value];
            if (caseEl) {
                [self.keyedSections setObject:element forKey:caseEl.value];
            } else {
                NSLog(@"No corresponding CASE for KEYB '%@'.", value);
            }
        }
        element = [self.parentList peek:1];
    }
}

- (void)configure
{
    if (!self.isKey) {
        [super configure];
        return;
    }
    
    [self readCases];
    
    if (self.keyedSections.count) {
        if (self.keyedSections.count != self.cases.count) {
            NSLog(@"Not all CASEs have corresponding KEYB sections.");
        }
    
        // Set initial value to first case
        ElementCASE *element = self.cases[0];
        id value = element.value;
        self.currentSection = self.keyedSections[value];
        [self validateValue:&value forKey:@"value" error:nil];
        [self setValue:value forKey:@"value"];
        [self.parentList insertElement:self.currentSection];
        
        // Use KVO to observe value change when data is first read
        // This saves us adding any key logic to the concrete element subclasses
        [self addObserver:self forKeyPath:@"value" options:0 context:nil];
        self.observing = YES;
    }
}

- (NSInteger)subElementCount
{
    return [self.currentSection subElementCount];
}

- (Element *)subElementAtIndex:(NSInteger)n
{
    return [self.currentSection subElementAtIndex:n];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context
{
    // In theory this will only run when the data is first read - update the displayed section to match the data
    [self setCase:[super transformedValue:[self valueForKey:@"value"]]];
    [self removeObserver:self forKeyPath:@"value"];
    self.observing = NO;
}

- (id)reverseTransformedValue:(id)value
{
    if (!self.isKey)
        return [super reverseTransformedValue:value];
    if (self.observing) {
        [self removeObserver:self forKeyPath:@"value"];
        self.observing = NO;
    }
    // Value is a CASE element - get the string value
    return [value value];
}

@end