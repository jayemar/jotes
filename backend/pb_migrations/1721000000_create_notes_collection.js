/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const collection = new Collection({
    type: "base",
    name: "notes",
    fields: [
      { name: "title", type: "text" },
      { name: "body", type: "text" },
      { name: "color_index", type: "number" },
      { name: "reminder_at", type: "text" },
      // Not added automatically by PocketBase (unlike the id field) - the
      // app's sync merge logic compares this timestamp to decide which
      // side of a conflict wins, so without it every fetched note would
      // report its created/updated as "now" instead of its real value.
      { name: "created", type: "autodate", onCreate: true, onUpdate: false },
      { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
    ],
    listRule: "@request.auth.id != ''",
    viewRule: "@request.auth.id != ''",
    createRule: "@request.auth.id != ''",
    updateRule: "@request.auth.id != ''",
    deleteRule: "@request.auth.id != ''",
  });

  app.save(collection);

  // jotes generates note ids as UUID v4 (36 chars, e.g.
  // "3fa85f64-5717-4562-b3fc-2c963f66afa6"), but PocketBase's default id
  // field (pattern ^[a-z0-9]+$, min/max 15) rejects both the hyphens and
  // the length, so every client-supplied id would fail on create. Relax
  // both to accept jotes' UUIDs. The id field only exists on the
  // collection after the first save, hence the second save here.
  const idField = collection.fields.getByName("id");
  idField.pattern = "^[a-z0-9-]+$";
  idField.min = 0;
  idField.max = 36;
  app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("notes");
  app.delete(collection);
});
