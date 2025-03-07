/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the "Elastic License
 * 2.0", the "GNU Affero General Public License v3.0 only", and the "Server Side
 * Public License v 1"; you may not use this file except in compliance with, at
 * your election, the "Elastic License 2.0", the "GNU Affero General Public
 * License v3.0 only", or the "Server Side Public License, v 1".
 */

package org.elasticsearch.action.admin.indices.template.post;

import org.elasticsearch.TransportVersions;
import org.elasticsearch.action.ActionResponse;
import org.elasticsearch.action.admin.indices.rollover.RolloverConfiguration;
import org.elasticsearch.cluster.metadata.ResettableValue;
import org.elasticsearch.cluster.metadata.Template;
import org.elasticsearch.common.io.stream.StreamOutput;
import org.elasticsearch.core.Nullable;
import org.elasticsearch.core.UpdateForV10;
import org.elasticsearch.xcontent.ParseField;
import org.elasticsearch.xcontent.ToXContentObject;
import org.elasticsearch.xcontent.XContentBuilder;

import java.io.IOException;
import java.util.List;
import java.util.Map;
import java.util.Objects;

/**
 * Contains the information on what V2 templates would match a given index.
 */
public class SimulateIndexTemplateResponse extends ActionResponse implements ToXContentObject {

    private static final ParseField TEMPLATE = new ParseField("template");
    private static final ParseField OVERLAPPING = new ParseField("overlapping");
    private static final ParseField NAME = new ParseField("name");
    private static final ParseField INDEX_PATTERNS = new ParseField("index_patterns");

    @Nullable
    // the resolved settings, mappings and aliases for the matched templates, if any
    private final Template resolvedTemplate;

    @Nullable
    // a map of template names and their index patterns that would overlap when matching the given index name
    private final Map<String, List<String>> overlappingTemplates;

    @Nullable
    private final RolloverConfiguration rolloverConfiguration;

    public SimulateIndexTemplateResponse(@Nullable Template resolvedTemplate, @Nullable Map<String, List<String>> overlappingTemplates) {
        this(resolvedTemplate, overlappingTemplates, null);
    }

    public SimulateIndexTemplateResponse(
        @Nullable Template resolvedTemplate,
        @Nullable Map<String, List<String>> overlappingTemplates,
        @Nullable RolloverConfiguration rolloverConfiguration
    ) {
        this.resolvedTemplate = resolvedTemplate;
        this.overlappingTemplates = overlappingTemplates;
        this.rolloverConfiguration = rolloverConfiguration;
    }

    public RolloverConfiguration getRolloverConfiguration() {
        return rolloverConfiguration;
    }

    /**
     * NB prior to 9.0 this was a TransportMasterNodeReadAction so for BwC we must remain able to write these responses until
     * we no longer need to support calling this action remotely.
     */
    @UpdateForV10(owner = UpdateForV10.Owner.DATA_MANAGEMENT)
    @Override
    public void writeTo(StreamOutput out) throws IOException {
        out.writeOptionalWriteable(resolvedTemplate);
        if (overlappingTemplates != null) {
            out.writeBoolean(true);
            out.writeInt(overlappingTemplates.size());
            for (Map.Entry<String, List<String>> entry : overlappingTemplates.entrySet()) {
                out.writeString(entry.getKey());
                out.writeStringCollection(entry.getValue());
            }
        } else {
            out.writeBoolean(false);
        }
        if (out.getTransportVersion().onOrAfter(TransportVersions.V_8_9_X)) {
            out.writeOptionalWriteable(rolloverConfiguration);
        }
        if (out.getTransportVersion().between(TransportVersions.V_8_14_0, TransportVersions.V_8_16_0)) {
            out.writeOptionalWriteable(null);
        }
    }

    @Override
    public XContentBuilder toXContent(XContentBuilder builder, Params params) throws IOException {
        builder.startObject();
        if (resolvedTemplate != null) {
            builder.field(TEMPLATE.getPreferredName());
            resolvedTemplate.toXContent(builder, ResettableValue.hideResetValues(params), rolloverConfiguration);
        }
        if (this.overlappingTemplates != null) {
            builder.startArray(OVERLAPPING.getPreferredName());
            for (Map.Entry<String, List<String>> entry : overlappingTemplates.entrySet()) {
                builder.startObject();
                builder.field(NAME.getPreferredName(), entry.getKey());
                builder.stringListField(INDEX_PATTERNS.getPreferredName(), entry.getValue());
                builder.endObject();
            }
            builder.endArray();
        }
        builder.endObject();
        return builder;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) {
            return true;
        }
        if (o == null || getClass() != o.getClass()) {
            return false;
        }
        SimulateIndexTemplateResponse that = (SimulateIndexTemplateResponse) o;
        return Objects.equals(resolvedTemplate, that.resolvedTemplate)
            && Objects.deepEquals(overlappingTemplates, that.overlappingTemplates)
            && Objects.equals(rolloverConfiguration, that.rolloverConfiguration);
    }

    @Override
    public int hashCode() {
        return Objects.hash(resolvedTemplate, overlappingTemplates, rolloverConfiguration);
    }

    @Override
    public String toString() {
        return "SimulateIndexTemplateResponse{"
            + "resolved template="
            + resolvedTemplate
            + ", overlapping templates="
            + String.join("|", overlappingTemplates.keySet())
            + "}";
    }
}
