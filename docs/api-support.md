# API v2 contract inventory

Source: public demo account WSDLs fetched over HTTPS on 2026-10-28.

These are upstream contracts, not response recordings. The account-specific WSDL/XSD
inventories were compared successfully on 2026-10-30. See [live validation](live-validation.md)
for JSON-envelope differences and sanitized regression fixtures.

| Service | Operation | POST request parts | Response parts |
| --- | --- | --- | --- |
| activity | add | sessionId: `xsd:string`, activity: `nsc:Activity` | activity: `nsc:Activity` |
| activity | update | sessionId: `xsd:string`, activity: `nsc:Activity` | activity: `nsc:Activity` |
| activity | remove | sessionId: `xsd:string`, id: `xsd:integer` | status: `xsd:boolean` |
| activity | getList | sessionId: `xsd:string`, filter: `nsc:ActivityListFilter`, offset: `xsd:integer`, count: `xsd:integer`, withFiles: `xsd:boolean`, withNames: `xsd:boolean` | list: `nsc:ActivityList` |
| activity | getFilesList | sessionId: `xsd:string`, filter: `nsc:ActivityListFilter`, offset: `xsd:integer`, count: `xsd:integer` | list: `nsc:FileList` |
| activity | getById | sessionId: `xsd:string`, id: `xsd:integer`, withNames: `xsd:boolean` | activity: `nsc:Activity` |
| activity | attachFiles | sessionId: `xsd:string`, activityId: `xsd:integer`, files: `nsc:FileList` | status: `xsd:boolean` |
| activity | removeFile | sessionId: `xsd:string`, id: `xsd:integer` | status: `xsd:boolean` |
| activity | downloadFile | sessionId: `xsd:string`, id: `xsd:integer`, stream: `xsd:boolean` | file: `nsc:File` |
| activity | getResizeImg | Declared message only; no POST binding | Unsupported |
| authentication | signIn | login: `xsd:string`, password: `xsd:string` | auth: `nsc:AuthToken` |
| authentication | signOut | sessionId: `xsd:string` | signOutState: `xsd:boolean` |
| authentication | getAuthorizedUser | sessionId: `xsd:string` | user: `nsc:User` |
| authentication | nop | sessionId: `xsd:string` | nopState: `xsd:boolean` |
| authentication | isSsl |  | isSsl: `xsd:boolean` |
| projects | add | sessionId: `xsd:string`, project: `nsc:Project` | project: `nsc:Project` |
| projects | update | sessionId: `xsd:string`, project: `nsc:Project` | project: `nsc:Project` |
| projects | remove | sessionId: `xsd:string`, id: `xsd:integer` | status: `xsd:boolean` |
| projects | getById | sessionId: `xsd:string`, id: `xsd:integer` | project: `nsc:Project` |
| projects | getAll | sessionId: `xsd:string`, loadTeam: `xsd:boolean` | list: `nsc:ProjectList` |
| projects | getList | sessionId: `xsd:string`, filter: `nsc:ProjectListFilter`, offset: `xsd:integer`, count: `xsd:integer`, loadTeam: `xsd:boolean` | list: `nsc:ProjectList` |
| projectsgroups | add | sessionId: `xsd:string`, group: `nsc:ProjectsGroup` | group: `nsc:ProjectsGroup` |
| projectsgroups | update | sessionId: `xsd:string`, group: `nsc:ProjectsGroup` | group: `nsc:ProjectsGroup` |
| projectsgroups | remove | sessionId: `xsd:string`, id: `xsd:integer` | status: `xsd:boolean` |
| projectsgroups | getById | sessionId: `xsd:string`, id: `xsd:integer` | group: `nsc:ProjectsGroup` |
| projectsgroups | getAll | sessionId: `xsd:string` | list: `nsc:ProjectsGroupList` |
| tasks | add | sessionId: `xsd:string`, task: `nsc:Task` | task: `nsc:Task` |
| tasks | update | sessionId: `xsd:string`, task: `nsc:Task` | task: `nsc:Task` |
| tasks | remove | sessionId: `xsd:string`, id: `xsd:integer` | status: `xsd:boolean` |
| tasks | getById | sessionId: `xsd:string`, id: `xsd:integer` | task: `nsc:Task` |
| tasks | getList | sessionId: `xsd:string`, filter: `nsc:TaskListFilter`, offset: `xsd:integer`, count: `xsd:integer`, loadTeam: `xsd:boolean` | list: `nsc:TaskList` |
| users | add | sessionId: `xsd:string`, user: `nsc:User` | user: `nsc:User` |
| users | update | sessionId: `xsd:string`, user: `nsc:User` | user: `nsc:User` |
| users | remove | sessionId: `xsd:string`, id: `xsd:integer` | status: `xsd:boolean` |
| users | getById | sessionId: `xsd:string`, id: `xsd:integer` | user: `nsc:User` |
| users | getByEmail | sessionId: `xsd:string`, email: `xsd:string` | user: `nsc:User` |
| users | getAll | sessionId: `xsd:string` | sessionId: `xsd:string`, list: `nsc:UserList` |
| users | getAuthorizedUser | sessionId: `xsd:string` | user: `nsc:User` |

## Known discrepancies and limits

- Activity getResizeImg has request/response messages but no POST binding; it is deliberately excluded from callable operations.
- The schema declares AuthToken twice; do not assume strict XSD validation succeeds.
- Help reference contains GET/POST path inconsistencies. Use WSDL POST bindings.
- Activity getList help text calls its result GroupList; WSDL declares ActivityList.
- Users getAll declares sessionId alongside list in its response. Preserve the whole response.
- HTTP-200 numeric API errors, data wrappers and binary downloads are covered by live checks.
- Pagination and read retries are bounded opt-ins. There is no date/time conversion or URL fetching.
- No credentials were used to fetch these contracts.

Sources: https://www.5pmweb.com/5pm_api.php and https://www.5pmweb.com/help/api_docs.php

## Snapshot checksums

- `activity.wsdl`: `381ef30b11b407778e9d899b4aa77b4d8b53b99d116fafd515f1f5ea33753fcc`
- `authentication.wsdl`: `e5e408bd08ad40f1daa0d65038975aa2e8230a39d0ba25f126995a5173ace132`
- `projects.wsdl`: `4686919f3a5ec647a5d9ed067e2c85bd93065ea43a25bae52326e37582975486`
- `projectsgroups.wsdl`: `ade39f53b9be0aa081221a7dbc1fe63bdd7317e6c3c1e8bdca4dfa993c852604`
- `schema.xsd`: `aa938cd35e979479b3559bbd04327fc9d91c3ce5ac860635e4465aa2a65827a8`
- `tasks.wsdl`: `d8cabc28841b33515f9c23ab5d1ca9f5975b486f173c98bcde5026f05a59480f`
- `users.wsdl`: `a660022447f04d7c32e92768eb77e8e6568b56bc775bd9f3c66152b1227d9bdc`
