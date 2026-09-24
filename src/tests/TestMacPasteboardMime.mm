#include <QApplication>
#include <QClipboard>
#include <QMimeData>
#include <QtTest/QTest>

#include <Qsci/qsciscintilla.h>

#import <AppKit/AppKit.h>

static NSString *const rectangularUti = @"com.scintilla.utf16-plain-text.rectangular";

// Preserve the user's clipboard even when a test assertion fails.
class ClipboardRestorer
{
public:
    ClipboardRestorer() : items([[NSMutableArray alloc] init])
    {
        for (NSPasteboardItem *source in [[NSPasteboard generalPasteboard] pasteboardItems])
        {
            NSPasteboardItem *copy = [[NSPasteboardItem alloc] init];
            for (NSString *type in [source types])
            {
                NSData *data = [source dataForType:type];
                if (data)
                    [copy setData:data forType:type];
            }
            [items addObject:copy];
            [copy release];
        }
    }

    ~ClipboardRestorer()
    {
        QApplication::clipboard()->clear();
        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
        [pasteboard clearContents];
        if ([items count])
            [pasteboard writeObjects:items];
        [items release];
    }

private:
    NSMutableArray *items;
};

static void writeNativeText(NSPasteboard *pasteboard, const QString &text, bool rectangular)
{
    NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
    [item setString:text.toNSString() forType:NSPasteboardTypeString];
    if (rectangular)
        [item setData:[NSData data] forType:rectangularUti];
    [pasteboard clearContents];
    [pasteboard writeObjects:@[item]];
    [item release];
}

// Feed a native pasteboard through Cocoa's actual drag destination callbacks.
// No Qt private headers or system-wide synthetic mouse events are required.
@interface TestNativeDrag : NSObject
@property(nonatomic, assign) NSPasteboard *draggingPasteboard;
@property(nonatomic, assign) NSPoint draggingLocation;
- (NSDragOperation)draggingSourceOperationMask;
@end

@implementation TestNativeDrag
- (NSDragOperation)draggingSourceOperationMask
{
    return NSDragOperationCopy;
}
@end

class TestEditor : public QsciScintilla
{
public:
    TestEditor() { setUtf8(true); }
    using QsciScintillaBase::toMimeData;
};

class TestMacPasteboardMime : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase()
    {
        if (QGuiApplication::platformName() != QStringLiteral("cocoa"))
            QSKIP("Native macOS clipboard tests require the Cocoa platform plugin.");
        if (QGuiApplication::screens().isEmpty())
            QSKIP("Native macOS clipboard tests require a graphical session.");
    }

    void exportNative_data() { textCases(); }
    void importNative_data() { textCases(); }
    void nativeDrop_data() { textCases(); }

    void exportNative()
    {
        QFETCH(QString, text);
        QFETCH(bool, rectangular);
        ClipboardRestorer restore;
        TestEditor editor;
        QApplication::clipboard()->setMimeData(editor.toMimeData(text.toUtf8(), rectangular));

        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
        QCOMPARE(QString::fromNSString([pasteboard stringForType:NSPasteboardTypeString]), text);
        QCOMPARE(bool([[pasteboard types] containsObject:rectangularUti]), rectangular);
        if (rectangular)
        {
            // An empty marker is still a present format, not a failed conversion.
            NSData *marker = [pasteboard dataForType:rectangularUti];
            QVERIFY(marker != nil);
            QCOMPARE([marker length], NSUInteger(0));
        }
    }

    void importNative()
    {
        QFETCH(QString, text);
        QFETCH(bool, rectangular);
        ClipboardRestorer restore;
        TestEditor editor;
        editor.setText("xx\nxx\n");
        editor.setCursorPosition(0, 1);

        // Publish native data rather than reading back Qt's cached QMimeData.
        writeNativeText([NSPasteboard generalPasteboard], text, rectangular);
        editor.paste();
        QCOMPARE(editor.text(), pastedText(text, rectangular));
    }

    void copyAndPasteRectangular()
    {
        ClipboardRestorer restore;
        TestEditor source;
        source.setText("abc\ndef\n");
        source.SendScintilla(QsciScintillaBase::SCI_SETSELECTIONMODE,
                QsciScintillaBase::SC_SEL_RECTANGLE);
        source.SendScintilla(QsciScintillaBase::SCI_SETRECTANGULARSELECTIONANCHOR, 1);
        source.SendScintilla(QsciScintillaBase::SCI_SETRECTANGULARSELECTIONCARET, 6);
        source.copy();
        QVERIFY([[[NSPasteboard generalPasteboard] types] containsObject:rectangularUti]);

        TestEditor target;
        target.setText("xx\nxx\n");
        target.setCursorPosition(0, 1);
        target.paste();
        QCOMPARE(target.text(), QString("xbx\nxex\n"));
    }

    void nativeDrop()
    {
        QFETCH(QString, text);
        QFETCH(bool, rectangular);
        TestEditor editor;
        editor.setText("xx\nxx\n");
        editor.resize(400, 200);
        editor.show();
        QVERIFY(QTest::qWaitForWindowExposed(&editor));

        NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
        writeNativeText(pasteboard, text, rectangular);
        NSView *view = reinterpret_cast<NSView *>(editor.winId());

        // Valid QScintilla drags always contain plain text as well as the marker.
        // Cocoa's standard text registration therefore admits the native drag.
        QVERIFY([[view registeredDraggedTypes] containsObject:NSPasteboardTypeString]);
        const int x = editor.SendScintilla(QsciScintillaBase::SCI_POINTXFROMPOSITION, 0, 1);
        const int y = editor.SendScintilla(QsciScintillaBase::SCI_POINTYFROMPOSITION, 0, 1)
                + editor.SendScintilla(QsciScintillaBase::SCI_TEXTHEIGHT, 0) / 2;
        const QPoint point = editor.viewport()->mapTo(&editor, QPoint(x, y));

        TestNativeDrag *drag = [[[TestNativeDrag alloc] init] autorelease];
        drag.draggingPasteboard = pasteboard;
        drag.draggingLocation = [view convertPoint:NSMakePoint(point.x(), point.y()) toView:nil];
        const NSDragOperation action = [view draggingEntered:(id<NSDraggingInfo>)drag];
        const bool dropped = [view performDragOperation:(id<NSDraggingInfo>)drag];
        [pasteboard releaseGlobally];

        QCOMPARE(action, NSDragOperationCopy);
        QVERIFY(dropped);
        QCOMPARE(editor.text(), pastedText(text, rectangular));
    }

private:
    static void textCases()
    {
        QTest::addColumn<QString>("text");
        QTest::addColumn<bool>("rectangular");
        QTest::newRow("plain-ascii") << QString("A\nB") << false;
        QTest::newRow("rectangular-ascii") << QString("A\nB") << true;
        QTest::newRow("plain-unicode") << QString::fromUtf8("가🙂\n나🚀") << false;
        QTest::newRow("rectangular-unicode") << QString::fromUtf8("가🙂\n나🚀") << true;
    }

    static QString pastedText(const QString &text, bool rectangular)
    {
        if (rectangular)
        {
            const QStringList lines = text.split('\n');
            return "x" + lines.at(0) + "x\nx" + lines.at(1) + "x\n";
        }
        return "x" + text + "x\nxx\n";
    }
};

QTEST_MAIN(TestMacPasteboardMime)
#include "TestMacPasteboardMime.moc"
