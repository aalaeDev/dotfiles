// GTK3 module: open file pickers on an editable path instead of the button bar, filled with the current folder.
// GTK has no setting for this: it ignores location-mode when a picker opens.
// Save pickers are left alone, since their name field is already in that spot.
#include <gtk/gtk.h>

static GQuark seen_quark;

static void find_entry(GtkWidget *widget, gpointer data) {
    GtkWidget **found = data;
    if (*found) return;
    if (g_strcmp0(G_OBJECT_TYPE_NAME(widget), "GtkFileChooserEntry") == 0) {
        *found = widget;
    } else if (GTK_IS_CONTAINER(widget)) {
        gtk_container_forall(GTK_CONTAINER(widget), find_entry, found);
    }
}

static GtkWidget *entry_of(GtkWidget *chooser) {
    GtkWidget *entry = NULL;
    find_entry(chooser, &entry);
    return entry;
}

static gboolean fill_path(gpointer data) {
    GtkWidget *chooser = data;
    GtkWidget *entry = entry_of(chooser);
    if (!entry || !gtk_widget_get_mapped(entry)) {
        g_signal_emit_by_name(chooser, "location-toggle-popup");
        entry = entry_of(chooser);
    }
    char *folder = gtk_file_chooser_get_current_folder(GTK_FILE_CHOOSER(chooser));
    if (entry && folder) {
        char *path = g_str_has_suffix(folder, "/") ? g_strdup(folder) : g_strconcat(folder, "/", NULL);
        gtk_entry_set_text(GTK_ENTRY(entry), path);
        gtk_editable_set_position(GTK_EDITABLE(entry), -1);
        g_free(path);
    }
    g_free(folder);
    g_object_unref(chooser);
    return G_SOURCE_REMOVE;
}

static void queue_fill(GtkWidget *chooser) {
    g_idle_add(fill_path, g_object_ref(chooser));
}

static gboolean on_map(GSignalInvocationHint *hint, guint n, const GValue *values, gpointer data) {
    GObject *object = g_value_get_object(&values[0]);
    if (!GTK_IS_FILE_CHOOSER_WIDGET(object) || g_object_get_qdata(object, seen_quark)) return TRUE;
    g_object_set_qdata(object, seen_quark, GINT_TO_POINTER(1));

    GtkFileChooserAction action = gtk_file_chooser_get_action(GTK_FILE_CHOOSER(object));
    if (action == GTK_FILE_CHOOSER_ACTION_OPEN || action == GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER) {
        g_signal_connect(object, "current-folder-changed", G_CALLBACK(queue_fill), NULL);
        queue_fill(GTK_WIDGET(object));
    }
    return TRUE;
}

G_MODULE_EXPORT void gtk_module_init(gint *argc, gchar ***argv) {
    seen_quark = g_quark_from_static_string("gtk-path-entry-seen");
    g_type_class_ref(GTK_TYPE_WIDGET);
    g_signal_add_emission_hook(g_signal_lookup("map", GTK_TYPE_WIDGET), 0, on_map, NULL, NULL);
}
