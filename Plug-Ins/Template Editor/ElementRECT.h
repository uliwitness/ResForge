#import "Element.h"

@interface ElementRECT : Element
@property SInt16 top;
@property SInt16 left;
@property SInt16 bottom;
@property SInt16 right;

+ (void)configureFields:(NSArray *)fields inView:(NSView *)view forElement:(Element *)element;

@end