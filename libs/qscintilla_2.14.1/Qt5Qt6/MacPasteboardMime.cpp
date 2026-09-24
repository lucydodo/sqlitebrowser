// This module implements part of the support for rectangular selections on
// macOS.  It is a separate file to avoid clashes between macOS and Scintilla
// data types.
//
// Copyright (c) 2023 Riverbank Computing Limited <info@riverbankcomputing.com>
// 
// This file is part of QScintilla.
// 
// This file may be used under the terms of the GNU General Public License
// version 3.0 as published by the Free Software Foundation and appearing in
// the file LICENSE included in the packaging of this file.  Please review the
// following information to ensure the GNU General Public License version 3.0
// requirements will be met: http://www.gnu.org/copyleft/gpl.html.
// 
// If you do not wish to use this file under the terms of the GPL version 3.0
// then you may purchase a commercial license.  For more information contact
// info@riverbankcomputing.com.
// 
// This file is provided AS IS with NO WARRANTY OF ANY KIND, INCLUDING THE
// WARRANTY OF DESIGN, MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.


#include <qglobal.h>

#if defined(Q_OS_MACOS)

#include <QByteArray>
#include <QLatin1String>
#include <QList>
#include <QString>
#include <QStringList>
#include <QVariant>

#if QT_VERSION >= QT_VERSION_CHECK(6, 5, 0)
#include <QUtiMimeConverter>
#elif QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
#include <QMacPasteboardMime>
#else
#error Native rectangular clipboard support on macOS requires Qt 6.5 or later.
#endif


static const QLatin1String mimeRectangular("text/x-qscintilla-rectangular");
static const QLatin1String utiRectangularMac("com.scintilla.utf16-plain-text.rectangular");


#if QT_VERSION >= QT_VERSION_CHECK(6, 5, 0)
class RectangularPasteboardMime : public QUtiMimeConverter
{
public:
    QList<QByteArray> convertFromMime(const QString &, const QVariant &data,
            const QString &) const override
    {
        return {data.toByteArray()};
    }

    QVariant convertToMime(const QString &, const QList<QByteArray> &data,
            const QString &) const override
    {
        QByteArray converted;

        for (const QByteArray &item : data)
            converted += item;

        return converted;
    }

    QString utiForMime(const QString &mime) const override
    {
        return mime == mimeRectangular ? QString(utiRectangularMac) : QString();
    }

    QString mimeForUti(const QString &uti) const override
    {
        return uti == utiRectangularMac ? QString(mimeRectangular) : QString();
    }
};
#else
class RectangularPasteboardMime : public QMacPasteboardMime
{
public:
    RectangularPasteboardMime() : QMacPasteboardMime(MIME_ALL)
    {
    }

    bool canConvert(const QString &mime, QString flav)
    {
        return mime == mimeRectangular && flav == utiRectangularMac;
    }

    QList<QByteArray> convertFromMime(const QString &, QVariant data, QString)
    {
        QList<QByteArray> converted;

        converted.append(data.toByteArray());

        return converted;
    }

    QVariant convertToMime(const QString &, QList<QByteArray> data, QString)
    {
        QByteArray converted;

        foreach (QByteArray i, data)
        {
            converted += i;
        }

        return QVariant(converted);
    }

    QString convertorName()
    {
        return QString("QScintillaRectangular");
    }

    QString flavorFor(const QString &mime)
    {
        if (mime == mimeRectangular)
            return QString(utiRectangularMac);

        return QString();
    }

    QString mimeFor(QString flav)
    {
        if (flav == utiRectangularMac)
            return QString(mimeRectangular);

        return QString();
    }
};
#endif


// Initialise the singleton instance.
void initialiseRectangularPasteboardMime()
{
    static RectangularPasteboardMime *instance = 0;

    if (!instance)
    {
        instance = new RectangularPasteboardMime();

#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
        qRegisterDraggedTypes(QStringList(utiRectangularMac));
#else
        // Qt 6 registers the converter on construction. QScintilla drags also
        // contain text/plain, which Cocoa already accepts, so they do not need
        // a separate registration for the rectangular selection marker.
#endif
    }
}


#endif
