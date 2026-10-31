package com.osf.orderintake;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Builds the payload the Gmail IMAP listener produces (email connector StoredEmailContent): a text body and a
 * map of attachment name to a stream typed with the Content-Type of its email part. That media type is what
 * makes DataWeave parse Excel, CSV or JSON attachments when it reads them.
 * The Mule API classes (TypedValue, DataType) come from the runtime MUnit runs in, so they are used through
 * reflection; a compile-time mule-api dependency cannot be resolved from Anypoint Exchange in CI.
 */
public final class EmailFixtures {
    private static final String METADATA = "org.mule.runtime.api.metadata.";

    private EmailFixtures() {
    }

    public static Map<String, Object> email(String body, String attachmentName, String contentType, String resource) throws Exception {
        byte[] bytes;
        try (InputStream in = EmailFixtures.class.getClassLoader().getResourceAsStream(resource)) {
            if (in == null) {
                throw new IOException("Test resource not found: " + resource);
            }
            bytes = in.readAllBytes();
        }
        Map<String, Object> attachments = new LinkedHashMap<>();
        attachments.put(attachmentName, typedValue(new ByteArrayInputStream(bytes), InputStream.class, contentType));
        Map<String, Object> email = new LinkedHashMap<>();
        email.put("body", typedValue(body, String.class, "text/plain"));
        email.put("attachments", attachments);
        return email;
    }

    /** new TypedValue(value, DataType.builder().type(type).mediaType(mediaType).build()) */
    private static Object typedValue(Object value, Class<?> type, String mediaType) throws Exception {
        ClassLoader loader = EmailFixtures.class.getClassLoader();
        Class<?> dataType = Class.forName(METADATA + "DataType", true, loader);
        Object builder = dataType.getMethod("builder").invoke(null);
        Object params = Class.forName(METADATA + "DataTypeBuilder", true, loader).getMethod("type", Class.class).invoke(builder, type);
        Class<?> paramsBuilder = Class.forName(METADATA + "DataTypeParamsBuilder", true, loader);
        params = paramsBuilder.getMethod("mediaType", String.class).invoke(params, mediaType);
        Object built = paramsBuilder.getMethod("build").invoke(params);
        return Class.forName(METADATA + "TypedValue", true, loader).getConstructor(Object.class, dataType).newInstance(value, built);
    }
}
