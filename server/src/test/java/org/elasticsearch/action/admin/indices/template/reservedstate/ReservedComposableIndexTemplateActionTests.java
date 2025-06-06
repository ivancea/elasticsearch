/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the "Elastic License
 * 2.0", the "GNU Affero General Public License v3.0 only", and the "Server Side
 * Public License v 1"; you may not use this file except in compliance with, at
 * your election, the "Elastic License 2.0", the "GNU Affero General Public
 * License v3.0 only", or the "Server Side Public License, v 1".
 */

package org.elasticsearch.action.admin.indices.template.reservedstate;

import org.elasticsearch.action.admin.indices.template.delete.TransportDeleteComponentTemplateAction;
import org.elasticsearch.action.admin.indices.template.delete.TransportDeleteComposableIndexTemplateAction;
import org.elasticsearch.action.admin.indices.template.put.PutComponentTemplateAction;
import org.elasticsearch.action.admin.indices.template.put.TransportPutComponentTemplateAction;
import org.elasticsearch.action.admin.indices.template.put.TransportPutComposableIndexTemplateAction;
import org.elasticsearch.action.support.ActionFilters;
import org.elasticsearch.cluster.ClusterName;
import org.elasticsearch.cluster.ClusterState;
import org.elasticsearch.cluster.metadata.ComposableIndexTemplate;
import org.elasticsearch.cluster.metadata.DataStreamGlobalRetentionSettings;
import org.elasticsearch.cluster.metadata.IndexMetadata;
import org.elasticsearch.cluster.metadata.Metadata;
import org.elasticsearch.cluster.metadata.MetadataCreateIndexService;
import org.elasticsearch.cluster.metadata.MetadataIndexTemplateService;
import org.elasticsearch.cluster.metadata.ProjectId;
import org.elasticsearch.cluster.metadata.ProjectMetadata;
import org.elasticsearch.cluster.metadata.ReservedStateHandlerMetadata;
import org.elasticsearch.cluster.metadata.ReservedStateMetadata;
import org.elasticsearch.cluster.project.TestProjectResolvers;
import org.elasticsearch.cluster.service.ClusterService;
import org.elasticsearch.common.settings.ClusterSettings;
import org.elasticsearch.common.settings.IndexScopedSettings;
import org.elasticsearch.common.settings.Settings;
import org.elasticsearch.core.Strings;
import org.elasticsearch.index.IndexService;
import org.elasticsearch.index.IndexSettingProviders;
import org.elasticsearch.index.mapper.MapperService;
import org.elasticsearch.indices.IndicesService;
import org.elasticsearch.indices.InvalidIndexTemplateException;
import org.elasticsearch.indices.SystemIndices;
import org.elasticsearch.reservedstate.ActionWithReservedState;
import org.elasticsearch.reservedstate.ReservedProjectStateHandler;
import org.elasticsearch.reservedstate.TransformState;
import org.elasticsearch.test.ESTestCase;
import org.elasticsearch.test.MockUtils;
import org.elasticsearch.threadpool.ThreadPool;
import org.elasticsearch.transport.TransportService;
import org.elasticsearch.xcontent.NamedXContentRegistry;
import org.elasticsearch.xcontent.XContentParseException;
import org.elasticsearch.xcontent.XContentParser;
import org.elasticsearch.xcontent.XContentParserConfiguration;
import org.elasticsearch.xcontent.XContentType;
import org.junit.Before;

import java.io.IOException;
import java.util.Collections;
import java.util.Map;
import java.util.Set;

import static java.util.Collections.singletonList;
import static org.elasticsearch.action.admin.indices.template.reservedstate.ReservedComposableIndexTemplateAction.reservedComponentName;
import static org.elasticsearch.action.admin.indices.template.reservedstate.ReservedComposableIndexTemplateAction.reservedComposableIndexName;
import static org.hamcrest.Matchers.aMapWithSize;
import static org.hamcrest.Matchers.allOf;
import static org.hamcrest.Matchers.containsInAnyOrder;
import static org.hamcrest.Matchers.empty;
import static org.hamcrest.Matchers.hasKey;
import static org.hamcrest.Matchers.hasSize;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.Mockito.doReturn;
import static org.mockito.Mockito.mock;

/**
 * A unit test class that tests {@link ReservedComposableIndexTemplateAction}
 */
public class ReservedComposableIndexTemplateActionTests extends ESTestCase {

    private MetadataIndexTemplateService templateService;
    private IndexScopedSettings indexScopedSettings;
    private IndicesService indicesService;
    private DataStreamGlobalRetentionSettings globalRetentionSettings;
    private ProjectId projectId;

    @Before
    public void setup() throws IOException {
        projectId = randomProjectIdOrDefault();

        final Settings settings = Settings.builder().put(IndexMetadata.SETTING_CREATION_DATE, System.currentTimeMillis()).build();
        indexScopedSettings = new IndexScopedSettings(settings, IndexScopedSettings.BUILT_IN_INDEX_SETTINGS);

        indicesService = mock(IndicesService.class);
        var indexService = mock(IndexService.class);
        var mapperService = mock(MapperService.class);
        doReturn(mapperService).when(indexService).mapperService();
        doReturn(indexService).when(indicesService).createIndex(any(), any(), anyBoolean());

        globalRetentionSettings = DataStreamGlobalRetentionSettings.create(ClusterSettings.createBuiltInClusterSettings());
        templateService = new MetadataIndexTemplateService(
            mock(ClusterService.class),
            mock(MetadataCreateIndexService.class),
            indicesService,
            indexScopedSettings,
            mock(NamedXContentRegistry.class),
            mock(SystemIndices.class),
            new IndexSettingProviders(Set.of()),
            globalRetentionSettings
        );
    }

    private <T> TransformState processJSON(
        ReservedProjectStateHandler<ReservedComposableIndexTemplateAction.ComponentsAndComposables> action,
        TransformState prevState,
        String json
    ) throws Exception {
        try (XContentParser parser = XContentType.JSON.xContent().createParser(XContentParserConfiguration.EMPTY, json)) {
            return action.transform(projectId, action.fromXContent(parser), prevState);
        }
    }

    public void testComponentValidation() {
        TransformState prevState = transformState();
        var action = new ReservedComposableIndexTemplateAction(templateService, indexScopedSettings);

        String badComponentJSON = """
            {
              "component_templates": {
                "template_1": {
                  "template": {
                    "_mappings": {
                      "properties": {
                        "@timestamp": {
                          "type": "date"
                        }
                      }
                    }
                  }
                }
              }
            }""";

        assertEquals(
            "[1:26] [component_template] failed to parse field [template]",
            expectThrows(XContentParseException.class, () -> processJSON(action, prevState, badComponentJSON)).getMessage()
        );
    }

    public void testComposableIndexValidation() {
        TransformState prevState = transformState();
        var action = new ReservedComposableIndexTemplateAction(templateService, indexScopedSettings);

        String badComponentJSON = """
            {
              "composable_index_templates": {
                "template_1": {
                  "index_patterns": ["te*", "bar*"],
                  "template": {
                    "settings": {
                      "number_of_shards": 1
                    },
                    "mappings": {
                      "_source": {
                        "enabled": true
                      },
                      "properties": {
                        "host_name": {
                          "type": "keyword"
                        },
                        "created_at": {
                          "type": "date",
                          "format": "EEE MMM dd HH:mm:ss Z yyyy"
                        }
                      }
                    },
                    "aliases": {
                      "mydata": { }
                    }
                  },
                  "priority": -500,
                  "composed_of": ["component_template1", "runtime_component_template"],
                  "version": 3,
                  "_meta": {
                    "description": "my custom"
                  }
                }
              }
            }""";

        assertEquals(
            "Validation Failed: 1: index template priority must be >= 0;",
            expectThrows(IllegalStateException.class, () -> processJSON(action, prevState, badComponentJSON)).getCause().getMessage()
        );

        String badComponentJSON1 = """
            {
              "composable_index_templates": {
                "template_1": {
                  "index_patterns": ["te*", "bar*"],
                  "template": {
                    "settings": {
                      "number_of_shards": 1
                    },
                    "mappings": {
                      "_source": {
                        "enabled": true
                      },
                      "properties": {
                        "host_name": {
                          "type": "keyword"
                        },
                        "created_at": {
                          "type": "date",
                          "format": "EEE MMM dd HH:mm:ss Z yyyy"
                        }
                      }
                    },
                    "aliases": {
                      "mydata": { }
                    }
                  },
                  "priority": 500,
                  "composed_of": ["component_template1", "runtime_component_template"],
                  "version": 3,
                  "_meta": {
                    "description": "my custom"
                  }
                }
              }
            }""";

        assertEquals(
            "index_template [template_1] invalid, cause [index template [template_1] specifies "
                + "component templates [component_template1, runtime_component_template] that do not exist]",
            expectThrows(InvalidIndexTemplateException.class, () -> processJSON(action, prevState, badComponentJSON1)).getMessage()
        );
    }

    public void testAddRemoveComponentTemplates() throws Exception {
        TransformState prevState = transformState();
        var action = new ReservedComposableIndexTemplateAction(templateService, indexScopedSettings);

        String emptyJSON = "";

        TransformState updatedState = processJSON(action, prevState, emptyJSON);
        assertThat(updatedState.keys(), empty());

        String settingsJSON = """
            {
              "component_templates": {
                "template_1": {
                  "template": {
                    "mappings": {
                      "properties": {
                        "@timestamp": {
                          "type": "date"
                        }
                      }
                    }
                  }
                },
                "template_2": {
                  "template": {
                    "mappings": {
                      "runtime": {
                        "day_of_week": {
                          "type": "keyword",
                          "script": {
                            "source": "emit(doc['@timestamp'].value.dayOfWeekEnum.getDisplayName(TextStyle.FULL, Locale.ENGLISH))"
                          }
                        }
                      }
                    }
                  }
                }
              }
            }""";

        prevState = updatedState;
        updatedState = processJSON(action, prevState, settingsJSON);
        assertThat(updatedState.keys(), containsInAnyOrder(reservedComponentName("template_1"), reservedComponentName("template_2")));

        String lessJSON = """
            {
              "component_templates": {
                "template_2": {
                  "template": {
                    "mappings": {
                      "runtime": {
                        "day_of_week": {
                          "type": "keyword",
                          "script": {
                            "source": "emit(doc['@timestamp'].value.dayOfWeekEnum.getDisplayName(TextStyle.FULL, Locale.ENGLISH))"
                          }
                        }
                      }
                    }
                  }
                }
              }
            }""";

        prevState = updatedState;
        updatedState = processJSON(action, prevState, lessJSON);
        assertThat(updatedState.keys(), containsInAnyOrder(reservedComponentName("template_2")));

        prevState = updatedState;
        updatedState = processJSON(action, prevState, emptyJSON);
        assertThat(updatedState.keys(), empty());
    }

    public void testAddRemoveIndexTemplates() throws Exception {
        TransformState prevState = transformState();
        var action = new ReservedComposableIndexTemplateAction(templateService, indexScopedSettings);

        String emptyJSON = "";

        TransformState updatedState = processJSON(action, prevState, emptyJSON);
        assertThat(updatedState.keys(), empty());

        String settingsJSON = """
            {
              "component_templates": {
                "component_template1": {
                  "template": {
                    "mappings": {
                      "properties": {
                        "@timestamp": {
                          "type": "date"
                        }
                      }
                    }
                  }
                },
                "runtime_component_template": {
                  "template": {
                    "mappings": {
                      "runtime": {
                        "day_of_week": {
                          "type": "keyword"
                        }
                      }
                    }
                  }
                }
              },
              "composable_index_templates": {
                "template_1": {
                    "index_patterns": ["te*", "bar*"],
                    "template": {
                      "settings": {
                        "number_of_shards": 1
                      },
                      "mappings": {
                        "_source": {
                          "enabled": true
                        },
                        "properties": {
                          "host_name": {
                            "type": "keyword"
                          },
                          "created_at": {
                            "type": "date",
                            "format": "EEE MMM dd HH:mm:ss Z yyyy"
                          }
                        }
                      },
                      "aliases": {
                        "mydata": { }
                      }
                    },
                    "priority": 500,
                    "composed_of": ["component_template1", "runtime_component_template"],
                    "version": 3,
                    "_meta": {
                      "description": "my custom"
                    }
                },
                "template_2": {
                    "index_patterns": ["foo*", "mar*"],
                    "template": {
                      "settings": {
                        "number_of_shards": 1
                      },
                      "mappings": {
                        "_source": {
                          "enabled": true
                        },
                        "properties": {
                          "host_name": {
                            "type": "keyword"
                          },
                          "created_at": {
                            "type": "date",
                            "format": "EEE MMM dd HH:mm:ss Z yyyy"
                          }
                        }
                      },
                      "aliases": {
                        "mydata": { }
                      }
                    },
                    "priority": 100,
                    "composed_of": ["component_template1", "runtime_component_template"],
                    "version": 3,
                    "_meta": {
                      "description": "my custom"
                    }
                }
              }
            }""";

        prevState = updatedState;
        updatedState = processJSON(action, prevState, settingsJSON);
        assertThat(
            updatedState.keys(),
            containsInAnyOrder(
                reservedComposableIndexName("template_1"),
                reservedComposableIndexName("template_2"),
                reservedComponentName("component_template1"),
                reservedComponentName("runtime_component_template")
            )
        );

        String lessJSON = """
            {
              "component_templates": {
                "component_template1": {
                  "template": {
                    "mappings": {
                      "properties": {
                        "@timestamp": {
                          "type": "date"
                        }
                      }
                    }
                  }
                },
                "runtime_component_template": {
                  "template": {
                    "mappings": {
                      "runtime": {
                        "day_of_week": {
                          "type": "keyword"
                        }
                      }
                    }
                  }
                }
              },
              "composable_index_templates": {
                "template_2": {
                    "index_patterns": ["te*", "bar*"],
                    "template": {
                      "settings": {
                        "number_of_shards": 1
                      },
                      "mappings": {
                        "_source": {
                          "enabled": true
                        },
                        "properties": {
                          "host_name": {
                            "type": "keyword"
                          },
                          "created_at": {
                            "type": "date",
                            "format": "EEE MMM dd HH:mm:ss Z yyyy"
                          }
                        }
                      },
                      "aliases": {
                        "mydata": { }
                      }
                    },
                    "priority": 500,
                    "composed_of": ["component_template1", "runtime_component_template"],
                    "version": 3,
                    "_meta": {
                      "description": "my custom"
                    }
                }
              }
            }""";

        prevState = updatedState;
        updatedState = processJSON(action, prevState, lessJSON);
        assertThat(
            updatedState.keys(),
            containsInAnyOrder(
                reservedComposableIndexName("template_2"),
                reservedComponentName("component_template1"),
                reservedComponentName("runtime_component_template")
            )
        );

        prevState = updatedState;
        updatedState = processJSON(action, prevState, emptyJSON);
        assertThat(updatedState.keys(), empty());
    }

    public void testAddRemoveIndexTemplatesWithOverlap() throws Exception {
        TransformState prevState = transformState();
        var action = new ReservedComposableIndexTemplateAction(templateService, indexScopedSettings);

        String emptyJSON = "";

        TransformState updatedState = processJSON(action, prevState, emptyJSON);
        assertThat(updatedState.keys(), empty());

        // Adding two composable index templates with same index patterns will fail
        String settingsJSON = """
            {
              "composable_index_templates": {
                "template_1": {
                    "index_patterns": ["te*", "bar*"],
                    "template": {
                      "settings": {
                        "number_of_shards": 1
                      },
                      "mappings": {
                        "_source": {
                          "enabled": true
                        },
                        "properties": {
                          "host_name": {
                            "type": "keyword"
                          },
                          "created_at": {
                            "type": "date",
                            "format": "EEE MMM dd HH:mm:ss Z yyyy"
                          }
                        }
                      },
                      "aliases": {
                        "mydata": { }
                      }
                    },
                    "priority": 500,
                    "version": 3,
                    "_meta": {
                      "description": "my custom"
                    }
                },
                "template_2": {
                    "index_patterns": ["te*", "bar*"],
                    "template": {
                      "settings": {
                        "number_of_shards": 1
                      },
                      "mappings": {
                        "_source": {
                          "enabled": true
                        },
                        "properties": {
                          "host_name": {
                            "type": "keyword"
                          },
                          "created_at": {
                            "type": "date",
                            "format": "EEE MMM dd HH:mm:ss Z yyyy"
                          }
                        }
                      },
                      "aliases": {
                        "mydata": { }
                      }
                    },
                    "priority": 500,
                    "version": 3,
                    "_meta": {
                      "description": "my custom"
                    }
                }
              }
            }""";

        var prevState1 = updatedState;

        assertTrue(
            expectThrows(IllegalArgumentException.class, () -> processJSON(action, prevState1, settingsJSON)).getMessage()
                .contains(
                    "index template [template_2] has index patterns [te*, bar*] " + "matching patterns from existing templates [template_1]"
                )
        );

        var newSettingsJSON = """
            {
              "composable_index_templates": {
                "template_1": {
                    "index_patterns": ["te*", "bar*"],
                    "template": {
                      "settings": {
                        "number_of_shards": 1
                      },
                      "mappings": {
                        "_source": {
                          "enabled": true
                        },
                        "properties": {
                          "host_name": {
                            "type": "keyword"
                          },
                          "created_at": {
                            "type": "date",
                            "format": "EEE MMM dd HH:mm:ss Z yyyy"
                          }
                        }
                      },
                      "aliases": {
                        "mydata": { }
                      }
                    },
                    "priority": 500,
                    "version": 3,
                    "_meta": {
                      "description": "my custom"
                    }
                }
              }
            }""";

        // We add one only to see if we can replace it subsequently, inserts happen before deletes in ReservedComposableIndexTemplateAction
        prevState = updatedState;
        updatedState = processJSON(action, prevState, newSettingsJSON);
        assertThat(updatedState.keys(), containsInAnyOrder(reservedComposableIndexName("template_1")));

        String lessJSON = """
            {
              "composable_index_templates": {
                "template_2": {
                    "index_patterns": ["te*", "bar*"],
                    "template": {
                      "settings": {
                        "number_of_shards": 1
                      },
                      "mappings": {
                        "_source": {
                          "enabled": true
                        },
                        "properties": {
                          "host_name": {
                            "type": "keyword"
                          },
                          "created_at": {
                            "type": "date",
                            "format": "EEE MMM dd HH:mm:ss Z yyyy"
                          }
                        }
                      },
                      "aliases": {
                        "mydata": { }
                      }
                    },
                    "priority": 500,
                    "version": 3,
                    "_meta": {
                      "description": "my custom"
                    }
                }
              }
            }""";

        // We are replacing template_1 with template_2, same index pattern, no validation should be thrown
        prevState = updatedState;
        updatedState = processJSON(action, prevState, lessJSON);
        assertThat(updatedState.keys(), containsInAnyOrder(reservedComposableIndexName("template_2")));

        prevState = updatedState;
        updatedState = processJSON(action, prevState, emptyJSON);
        assertThat(updatedState.keys(), empty());
    }

    public void testHandlerCorrectness() {
        final ThreadPool threadPool = mock(ThreadPool.class);
        TransportService transportService = MockUtils.setupTransportServiceWithThreadpoolExecutor(threadPool);
        var putIndexAction = new TransportPutComposableIndexTemplateAction(
            transportService,
            null,
            threadPool,
            null,
            mock(ActionFilters.class),
            TestProjectResolvers.alwaysThrow()
        );
        assertEquals(ReservedComposableIndexTemplateAction.NAME, putIndexAction.reservedStateHandlerName().get());
        assertThat(
            putIndexAction.modifiedKeys(new TransportPutComposableIndexTemplateAction.Request("aaa")),
            containsInAnyOrder(reservedComposableIndexName("aaa"))
        );
        var delIndexAction = new TransportDeleteComposableIndexTemplateAction(
            transportService,
            null,
            threadPool,
            null,
            mock(ActionFilters.class),
            TestProjectResolvers.alwaysThrow()
        );
        assertEquals(ReservedComposableIndexTemplateAction.NAME, delIndexAction.reservedStateHandlerName().get());
        assertThat(
            delIndexAction.modifiedKeys(new TransportDeleteComposableIndexTemplateAction.Request("a", "b")),
            containsInAnyOrder(reservedComposableIndexName("a"), reservedComposableIndexName("b"))
        );

        var putComponentAction = new TransportPutComponentTemplateAction(
            transportService,
            null,
            threadPool,
            null,
            mock(ActionFilters.class),
            indexScopedSettings,
            TestProjectResolvers.alwaysThrow()
        );
        assertEquals(ReservedComposableIndexTemplateAction.NAME, putComponentAction.reservedStateHandlerName().get());
        assertThat(
            putComponentAction.modifiedKeys(new PutComponentTemplateAction.Request("aaa")),
            containsInAnyOrder(reservedComponentName("aaa"))
        );

        var delComponentAction = new TransportDeleteComponentTemplateAction(
            transportService,
            null,
            threadPool,
            null,
            mock(ActionFilters.class),
            TestProjectResolvers.alwaysThrow()
        );
        assertEquals(ReservedComposableIndexTemplateAction.NAME, delComponentAction.reservedStateHandlerName().get());
        assertThat(
            delComponentAction.modifiedKeys(new TransportDeleteComponentTemplateAction.Request("a", "b")),
            containsInAnyOrder(reservedComponentName("a"), reservedComponentName("b"))
        );
    }

    public void testBlockUsingReservedComponentTemplates() throws Exception {
        TransformState prevState = transformState();
        var action = new ReservedComposableIndexTemplateAction(templateService, indexScopedSettings);

        String settingsJSON = """
            {
              "component_templates": {
                "template_1": {
                  "template": {
                    "mappings": {
                      "properties": {
                        "@timestamp": {
                          "type": "date"
                        }
                      }
                    }
                  }
                }
              }
            }""";

        var updatedState = processJSON(action, prevState, settingsJSON);

        ProjectMetadata withReservedState = ProjectMetadata.builder(updatedState.state().getMetadata().getProject(projectId))
            .put(
                ReservedStateMetadata.builder("test")
                    .putHandler(new ReservedStateHandlerMetadata(ReservedComposableIndexTemplateAction.NAME, updatedState.keys()))
                    .build()
            )
            .build();

        String composableTemplate = """
            {
              "composable_index_templates": {
                "composable_template_1": {
                    "index_patterns": ["te*", "bar*"],
                    "template": {
                      "settings": {
                        "number_of_shards": 1
                      },
                      "mappings": {
                        "_source": {
                          "enabled": true
                        },
                        "properties": {
                          "host_name": {
                            "type": "keyword"
                          },
                          "created_at": {
                            "type": "date",
                            "format": "EEE MMM dd HH:mm:ss Z yyyy"
                          }
                        }
                      },
                      "aliases": {
                        "mydata": { }
                      }
                    },
                    "priority": 500,
                    "composed_of": ["%s"],
                    "version": 3,
                    "_meta": {
                      "description": "my custom"
                    }
                  }
                }
              }
            }""";

        try (
            XContentParser parser = XContentType.JSON.xContent()
                .createParser(XContentParserConfiguration.EMPTY, Strings.format(composableTemplate, "template_1"))
        ) {
            var request = action.fromXContent(parser).composableTemplates().get(0);
            assertTrue(
                expectThrows(
                    IllegalArgumentException.class,
                    () -> TransportPutComposableIndexTemplateAction.verifyIfUsingReservedComponentTemplates(
                        request,
                        withReservedState.reservedStateMetadata().values()
                    )
                ).getMessage().contains("errors: [[component_template:template_1] is reserved by [test]]")
            );
        }

        try (
            XContentParser parser = XContentType.JSON.xContent()
                .createParser(XContentParserConfiguration.EMPTY, Strings.format(composableTemplate, "template_2"))
        ) {
            var request = action.fromXContent(parser).composableTemplates().get(0);
            // this should just work, no failure
            TransportPutComposableIndexTemplateAction.verifyIfUsingReservedComponentTemplates(
                request,
                withReservedState.reservedStateMetadata().values()
            );
        }
    }

    public void testTemplatesWithReservedPrefix() throws Exception {
        final String conflictingTemplateName = "validate_template";

        // Reserve the validate_template name in the reserved metadata
        String composableTemplate = Strings.format("""
            {
              "composable_index_templates": {
                "%s": {
                    "index_patterns": ["te*", "bar*"],
                    "template": {
                      "settings": {
                        "number_of_shards": 1
                      },
                      "mappings": {
                        "_source": {
                          "enabled": true
                        },
                        "properties": {
                          "host_name": {
                            "type": "keyword"
                          },
                          "created_at": {
                            "type": "date",
                            "format": "EEE MMM dd HH:mm:ss Z yyyy"
                          }
                        }
                      },
                      "aliases": {
                        "mydata": { }
                      }
                    },
                    "priority": 500,
                    "version": 3,
                    "_meta": {
                      "description": "my custom"
                    }
                  }
                }
              }
            }""", conflictingTemplateName);

        // add a non-reserved template into the cluster state that has a name of validate_template, but with the composable
        // index name prefix.
        ProjectMetadata project = ProjectMetadata.builder(projectId)
            .indexTemplates(
                Map.of(
                    reservedComposableIndexName(conflictingTemplateName),
                    ComposableIndexTemplate.builder()
                        .indexPatterns(singletonList("foo*"))
                        .componentTemplates(Collections.emptyList())
                        .priority(1L)
                        .version(1L)
                        .metadata(Collections.emptyMap())
                        .build()
                )
            )
            .build();

        ClusterService clusterService = mock(ClusterService.class);
        MetadataIndexTemplateService mockedTemplateService = new MetadataIndexTemplateService(
            clusterService,
            mock(MetadataCreateIndexService.class),
            indicesService,
            indexScopedSettings,
            mock(NamedXContentRegistry.class),
            mock(SystemIndices.class),
            new IndexSettingProviders(Set.of()),
            globalRetentionSettings
        );

        ClusterState state = ClusterState.builder(new ClusterName("elasticsearch"))
            .metadata(Metadata.builder().put(project).build())
            .build();
        doReturn(state).when(clusterService).state();

        // we should see the weird composable name prefixed 'validate_template'
        assertThat(project.templatesV2(), allOf(aMapWithSize(1), hasKey(reservedComposableIndexName(conflictingTemplateName))));

        TransformState prevState = transformState(project);
        var action = new ReservedComposableIndexTemplateAction(mockedTemplateService, indexScopedSettings);

        TransformState updatedState = processJSON(action, prevState, composableTemplate);

        // only one reserved key for 'validate_template'
        assertThat(updatedState.keys(), containsInAnyOrder(reservedComposableIndexName(conflictingTemplateName)));
        // we should find a template name with 'validate_template' and 'composable_index_template:validate_template'. The user had
        // added that weird name 'composable_index_template:validate_template', using this prefix in the name shouldn't make us fail
        // any reservation validation
        assertThat(
            updatedState.state().getMetadata().getProject(projectId).templatesV2(),
            allOf(aMapWithSize(2), hasKey(reservedComposableIndexName(conflictingTemplateName)), hasKey(conflictingTemplateName))
        );

        ProjectMetadata withReservedMetadata = ProjectMetadata.builder(updatedState.state().getMetadata().getProject(projectId))
            .put(
                new ReservedStateMetadata.Builder("file_settings").putHandler(
                    new ReservedStateHandlerMetadata(ReservedComposableIndexTemplateAction.NAME, updatedState.keys())
                ).build()
            )
            .build();

        TransportPutComposableIndexTemplateAction.Request pr = new TransportPutComposableIndexTemplateAction.Request(
            conflictingTemplateName
        );

        final ThreadPool threadPool = mock(ThreadPool.class);
        TransportService transportService = MockUtils.setupTransportServiceWithThreadpoolExecutor(threadPool);
        var putTemplateAction = new TransportPutComposableIndexTemplateAction(
            transportService,
            null,
            threadPool,
            null,
            mock(ActionFilters.class),
            TestProjectResolvers.alwaysThrow()
        );

        // Try fake REST modification request with validate_template, this will fail
        var modifiedKeys = putTemplateAction.modifiedKeys(pr);
        assertThat(modifiedKeys, hasSize(1));

        var fakeAction = new ActionWithReservedState<TransportPutComposableIndexTemplateAction.Request>() {
        };
        assertEquals(
            "Failed to process request [validate_template] with errors: "
                + "[[composable_index_template:validate_template] set as read-only by [file_settings]]",
            expectThrows(
                IllegalArgumentException.class,
                () -> fakeAction.validateForReservedState(
                    withReservedMetadata.reservedStateMetadata().values(),
                    ReservedComposableIndexTemplateAction.NAME,
                    modifiedKeys,
                    pr.name()
                )
            ).getMessage()
        );

        // Try fake REST modification request with the weird prefixed composable_index_template:validate_template, this will work, since
        // the reserved keys for that name would be composable_index_template:composable_index_template:validate_template and it will not
        // match our reserved state.
        var prOK = new TransportPutComposableIndexTemplateAction.Request(reservedComposableIndexName(conflictingTemplateName));
        var modifiedKeysOK = putTemplateAction.modifiedKeys(prOK);
        assertThat(modifiedKeysOK, hasSize(1));

        fakeAction.validateForReservedState(
            withReservedMetadata.reservedStateMetadata().values(),
            ReservedComposableIndexTemplateAction.NAME,
            modifiedKeysOK,
            prOK.name()
        );
    }

    private TransformState transformState() {
        return transformState(ProjectMetadata.builder(projectId).build());
    }

    private TransformState transformState(ProjectMetadata projectMetadata) {
        return new TransformState(
            ClusterState.builder(ClusterName.DEFAULT).putProjectMetadata(projectMetadata).build(),
            Collections.emptySet()
        );
    }
}
