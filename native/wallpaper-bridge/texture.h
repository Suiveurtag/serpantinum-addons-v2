#pragma once
#include <QQuickItem>
#include <QtQml/qqmlregistration.h>

class FrameStream;
class TextureProvider;
class GlassTexture : public QQuickItem {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString outputName READ outputName WRITE setOutputName NOTIFY outputNameChanged)
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)
public:
    explicit GlassTexture(QQuickItem* parent = nullptr);
    ~GlassTexture() override;
    QString outputName() const { return m_output; }
    bool active() const { return m_active; }
    bool ready() const;
    void setOutputName(const QString& value);
    void setActive(bool value);
    bool isTextureProvider() const override { return true; }
    QSGTextureProvider* textureProvider() const override;
signals:
    void outputNameChanged();
    void activeChanged();
    void readyChanged();
protected:
    QSGNode* updatePaintNode(QSGNode*, UpdatePaintNodeData*) override;
    void releaseResources() override;
private:
    void reconnect();
    QString m_output;
    bool m_active = false;
    FrameStream* m_stream = nullptr;
    mutable TextureProvider* m_provider = nullptr;
};
