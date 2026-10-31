package com.osf.orderintake;

import java.io.IOException;
import java.io.InputStream;
import java.util.LinkedHashMap;
import java.util.Map;

import org.mule.runtime.api.metadata.DataType;
import org.mule.runtime.api.metadata.TypedValue;
import org.mule.runtime.api.streaming.CursorProvider;
import org.mule.runtime.api.streaming.bytes.CursorStream;
import org.mule.runtime.api.streaming.bytes.CursorStreamProvider;

/**
 * Builds the payload the Gmail IMAP listener produces (email connector StoredEmailContent): a text body and a
 * map of attachment name to a repeatable stream, typed with the Content-Type of its email part. That media
 * type is what makes DataWeave parse Excel, CSV or JSON attachments when it reads them.
 */
public final class EmailFixtures {
    private EmailFixtures() {
    }

    public static Map<String, Object> email(String body, String attachmentName, String contentType, String resource) throws IOException {
        byte[] bytes;
        try (InputStream in = EmailFixtures.class.getClassLoader().getResourceAsStream(resource)) {
            if (in == null) {
                throw new IOException("Test resource not found: " + resource);
            }
            bytes = in.readAllBytes();
        }
        // Like the connector: the stream is a cursor provider and the media type is the part's Content-Type header
        DataType type = DataType.builder().type(CursorStreamProvider.class).mediaType(contentType).build();
        Map<String, TypedValue<Object>> attachments = new LinkedHashMap<>();
        attachments.put(attachmentName, new TypedValue<>(new BytesProvider(bytes), type));
        Map<String, Object> email = new LinkedHashMap<>();
        email.put("body", new TypedValue<>(body, DataType.builder().type(String.class).mediaType("text/plain").build()));
        email.put("attachments", attachments);
        return email;
    }

    private static final class BytesProvider implements CursorStreamProvider {
        private final byte[] bytes;
        private boolean closed;

        BytesProvider(byte[] bytes) {
            this.bytes = bytes;
        }

        @Override
        public CursorStream openCursor() {
            return new BytesCursor(this);
        }

        @Override
        public void close() {
            closed = true;
        }

        @Override
        public void releaseResources() {
        }

        @Override
        public boolean isClosed() {
            return closed;
        }
    }

    private static final class BytesCursor extends CursorStream {
        private final BytesProvider provider;
        private int position;
        private boolean released;

        BytesCursor(BytesProvider provider) {
            this.provider = provider;
        }

        @Override
        public int read() {
            return position < provider.bytes.length ? provider.bytes[position++] & 0xff : -1;
        }

        @Override
        public int read(byte[] b, int off, int len) {
            if (position >= provider.bytes.length) {
                return -1;
            }
            int n = Math.min(len, provider.bytes.length - position);
            System.arraycopy(provider.bytes, position, b, off, n);
            position += n;
            return n;
        }

        @Override
        public int available() {
            return provider.bytes.length - position;
        }

        @Override
        public long getPosition() {
            return position;
        }

        @Override
        public void seek(long target) {
            position = (int) target;
        }

        @Override
        public void release() {
            released = true;
        }

        @Override
        public boolean isReleased() {
            return released;
        }

        @Override
        public CursorProvider getProvider() {
            return provider;
        }

        @Override
        public void close() {
            released = true;
        }
    }
}
