
unit Main;
 {$DEFINE UNIDAC}  //закоментировать, если используется встроенная поддержка sqlite
interface


uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.StdCtrls,
  FMX.Grid.Style, FMX.Grid, FMX.ScrollBox, FMX.Controls.Presentation,
  FMX.Edit, FMX.Objects, FMX.Layouts, FMX.Platform, XSuperObject, System.IOUtils,
  System.JSON, System.Rtti, MemDS, FMX.Memo.Types,
  FMX.Memo
  , Threading
  , DateUtils
  {$IFDEF UNIDAC}
    , Data.DB, DBAccess, Uni, SQLiteUniProvider, UniProvider
  {$ELSE}
     , Data.SqlExpr, Data.FMTBcd, Data.DB, Data.DbxSqlite
  {$ENDIF}
  ;

type
  TMainForm = class(TForm)
    Memo1: TMemo;
    MainLayout: TLayout;
    TopLayout: TLayout;
    SearchEdit: TEdit;
    LoadButton: TButton;
    GridLayout: TLayout;
    SRGrid: TStringGrid;
    StringColumn1: TStringColumn;
    StringColumn2: TStringColumn;
    StringColumn3: TStringColumn;
    StringColumn4: TStringColumn;
    StringColumn5: TStringColumn;
    BottomLayout: TLayout;
    StatusLabel: TLabel;
    ProgressBar1: TProgressBar;
    SearchEditButton1: TSearchEditButton;
    CheckBox1: TCheckBox;
    Timer1: TTimer;
    TimeLabel: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure LoadButtonClick(Sender: TObject);
    procedure FormActivate(Sender: TObject);
    procedure SearchEditButton1Click(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
  private

    procedure LoadJSONFiles;
    procedure PerformSearch;
    procedure SetupGrid;
    procedure ProcessJSONFile(const FileName: string; const Language: string);
    procedure CopyFromClipboard;
  public
    { Public declarations }
  end;

var
  MainForm: TMainForm;
  {$IFDEF UNIDAC}
    SQLiteConnection: TUniConnection;
    SQLiteQuery: TUniQuery;
  {$ELSE}
    SQLiteConnection: TSQLConnection;
    SQLiteQuery: TSQLQuery;
  {$ENDIF}
  DatabaseInitialized: Boolean;
  ProgressValue: double;
  IsUpdating: boolean;
  StartTime: TDateTime;
implementation

{$R *.fmx}

function Dequote(SText: string): string;
begin
    Result:= SText.Replace('''','``');
end;

function Dedequote(SText: string): string;
begin
    Result:= SText.Replace('``','''');
end;

{$REGION 'SQLite'}
  procedure CreateSQLite (SQLiteDB:string);
    begin
    		try
  					{$IFDEF UNIDAC}
              if not assigned(SQLiteConnection)
              then SQLiteConnection:=TUniConnection.Create(nil);
              SQLiteConnection.ProviderName:= 'SQLite';
              SQLiteConnection.Database:= SQLiteDB ;
              SQLiteConnection.SpecificOptions. Values['Direct']:='False';
              SQLiteConnection.SpecificOptions.Values['ClientLibrary']:='sqlite3.dll';
              SQLiteConnection.SpecificOptions.Values['UseUnicode'] := 'True';
              SQLiteConnection.SpecificOptions.Values['JournalMode']:='jmMemory';
              SQLiteConnection.SpecificOptions.Values['DefaultCollations']:='False';
              SQLiteConnection.Options.KeepDesignConnected:= True;
              SQLiteConnection.LoginPrompt:= False;

             {$ELSE}
                if not assigned(SQLiteConnection)
                then SQLiteConnection:=TSQLConnection.Create(nil);
                SQLiteConnection.ConnectionName := 'SQLITECONNECTION';
                SQLiteConnection.KeepConnection:= True;
                SQLiteConnection.DriverName:='Sqlite';
                SQLiteConnection.Params.Clear;
                SQLiteConnection.Params.Add('Database='+SQLiteDB);
                SQLiteConnection.Params.Add('ColumnMetaDataSupported=true');
                SQLiteConnection.Params.Add('Extensions=true');
                SQLiteConnection.LoginPrompt:=false;
              {$ENDIF}
    		except on e: exception do
    		begin

    		end;
        end;
        try
    				if not assigned(SQLiteQuery) then
    				begin
    						{$IFDEF UNIDAC}
                  SQLiteQuery:= TUniQuery.Create(nil);
                  SQLiteQuery.Connection:= SQLiteConnection;
                {$ELSE}
                  SQLiteQuery:= TSQLQuery.Create(nil);
                  SQLiteQuery.SQLConnection:= SQLiteConnection;
                {$ENDIF}
    				end;
    		except on e: exception do

    		end;
    end;

  	procedure CreateDB (DBFileName:string);
  	var DBPath:string; SQLiteDB: TextFile; UpdateFlag:Boolean;
  	begin
  			UpdateFlag:=True;
        DBPath:=ExtractFileDir(Paramstr(0));
  			if not TDirectory.Exists( DBPath )
      	then TDirectory.CreateDirectory ( DBPath );
  			AssignFile(SQLiteDB, ( DBPath + PathDelim + DBFileName));
  			if not FileExists( DBPath + PathDelim +DBFileName)
  					then begin
  						Rewrite(SQLiteDB);
  						CloseFile(SQLiteDB);
  						UpdateFlag:=True;
  					end;
  			CreateSQLite(DBPath + PathDelim +DBFileName);
  			if UpdateFlag then
  			try
  					SQLiteQuery.Close;
  					SQLiteQuery.SQL.Text:='CREATE TABLE IF NOT EXISTS e1_translations (T_ID INTEGER PRIMARY KEY AUTOINCREMENT, ' +
                  'j_sections TEXT, j_key TEXT UNIQUE, j_en TEXT, j_ru TEXT);';
            SQLiteQuery.ExecSQL;
  					SQLiteQuery.SQL.Text := 'CREATE INDEX IF NOT EXISTS idx_j_en ON e1_translations(j_en)';
            SQLiteQuery.ExecSQL;
            SQLiteQuery.SQL.Text := 'CREATE INDEX IF NOT EXISTS idx_j_ru ON e1_translations(j_ru)';
            SQLiteQuery.ExecSQL;
            SQLiteQuery.SQL.Text := 'CREATE INDEX IF NOT EXISTS idx_j_key ON e1_translations(j_key)';
            SQLiteQuery.ExecSQL;
            SQLiteQuery.SQL.Text := 'CREATE INDEX IF NOT EXISTS idx_j_sections ON e1_translations(j_sections)';
            SQLiteQuery.ExecSQL;
            SQLiteQuery.SQL.Text:='CREATE TABLE if not exists e1_settings (S_ID INTEGER PRIMARY KEY AUTOINCREMENT UNIQUE, S_NAME VARCHAR (250) UNIQUE ON CONFLICT REPLACE, S_VALUE VARCHAR (250));';
						SQLiteQuery.ExecSQL;
            DatabaseInitialized := True;
  			except

  			end;
  	end;

{$ENDREGION}

procedure TMainForm.FormCreate(Sender: TObject);
begin
  DatabaseInitialized := False;
  CreateDB('translations.db');
  SetupGrid;
  IsUpdating:=false;
//  SQLiteQuery.SQL.Text := 'SELECT sqlite_version();';
//  SQLiteQuery.Open;

  //SearchEdit.Text:=SQLiteQuery.Fields[0].AsString;
//  SQLiteQuery.Close;

end;

procedure TMainForm.FormActivate(Sender: TObject);
begin
  CopyFromClipboard;
end;

procedure TMainForm.CopyFromClipboard;
var
  ClipboardService: IFMXClipboardService;
  ClipboardText: string;
begin
  if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, ClipboardService) then
  begin
    ClipboardText := ClipboardService.GetClipboard.ToString;
    if (ClipboardText <> '')
    then
    begin
      SearchEdit.Text := ClipboardText;
      PerformSearch;
    end;
  end;
end;

procedure SetClipboardText(CText: string);
var
  ClipboardService: IFMXClipboardService;
begin
  if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, ClipboardService)
  then ClipboardService.SetClipboard(CText);
end;

procedure TMainForm.SetupGrid;
begin
  StringColumn1.Header := 'ID';
  StringColumn1.Width := 50;

  StringColumn2.Header := 'Секция';
  StringColumn2.Width := 120;

  StringColumn3.Header := 'Ключ';
  StringColumn3.Width := 200;

  StringColumn4.Header := 'Английский';
  StringColumn4.Width := 300;

  StringColumn5.Header := 'Русский';
  StringColumn5.Width := 300;

  SRGrid.RowCount := 0;
end;

procedure TMainForm.Timer1Timer(Sender: TObject);
begin
    TimeLabel.Text:=FormatDateTime('nn:ss', SecondsBetween(Now, StartTime)/ SecsPerDay );
end;

procedure TMainForm.LoadButtonClick(Sender: TObject);
begin
  StartTime:=Now;
  Timer1.Enabled:= true;
  IsUpdating:=true;
  LoadJSONFiles;
end;

procedure TMainForm.LoadJSONFiles;
var
  EnPath, RuPath: string;
begin
  try
    EnPath := ExtractFilePath(ParamStr(0)) + 'en' + PathDelim + 'Game.json';
    RuPath := ExtractFilePath(ParamStr(0)) + 'ru' + PathDelim + 'Game.json';

    if not FileExists(EnPath) then
    begin
      ShowMessage('Не найден английский JSON ' + EnPath);
      Exit;
    end;

    if not FileExists(RuPath) then
    begin
      ShowMessage('Не найден русский JSON ' + RuPath);
      Exit;
    end;

    SQLiteQuery.SQL.Text := 'DELETE FROM e1_translations';
    SQLiteQuery.ExecSQL;
    TTask.Create(procedure
    begin
        LoadButton.Enabled:=false;
        IsUpdating:=true;
        ProgressValue:=0;
        ProcessJSONFile(EnPath, 'en');
        ProgressValue:=50;
        ProcessJSONFile(RuPath, 'ru');
        StatusLabel.Text := 'Загрузка завершена';
        ProgressBar1.Value:=0;
        IsUpdating:=false;
        LoadButton.Enabled:=true;
        Timer1.Enabled:= false;
    end).Start;
  except
    on E: Exception do
    begin
      ShowMessage('Ошибка загрузки файлов: ' + E.Message);
    end;
  end;
end;

procedure TMainForm.ProcessJSONFile(const FileName: string; const Language: string);
var
  Json: ISuperObject;
  Member, SubMember: IMember;
  SQty, KQty: integer;
  CS, CK: integer;
  SectionName, Key, Value: string;
begin
      try
        TThread.Synchronize (TThread.CurrentThread,
        procedure
        begin
          StatusLabel.Text:='Загрузка файла '+FileName;
        end);
        Json := SO(TFile.ReadAllText(FileName, TEncoding.UTF8));
        SQty:=Json.AsObject.Count;
        CS:=0;
        for Member in Json.AsObject do
        begin
            SectionName := Member.Name;
            CK:=0;
            KQty:=Member.AsObject.Count;
            for SubMember in Member.AsObject do
            begin
              TThread.Synchronize (TThread.CurrentThread,
              procedure
              begin
                StatusLabel.Text:='Обработка файла '+FileName+' '+Round(ProgressValue + (CS/SQty+(CK/KQty)/SQty)*100/2 ).ToString+'%';
                ProgressBar1.Value:=ProgressValue + (CS/SQty+(CK/KQty)/SQty)*100/2 ;
              end);

              Key := SubMember.Name;
              Value := SubMember.AsString;
              try
                SQLIteQuery.Close;
                SQLIteQuery.SQL.Text := 'INSERT INTO e1_translations (j_sections, j_key, j_'+Language+') '+
                		' VALUES ('''+Dequote(SectionName)+''', '''+Dequote(Key)+''', '''+Dequote(Value)+''') '+
                  	' ON CONFLICT (j_key) DO UPDATE SET j_'+Language+'= '''+Dequote(Value)+''' ;';
                SQLIteQuery.ExecSQL;
              except on e: exception do
                TThread.Synchronize (TThread.CurrentThread,
                procedure
                begin
                  ShowMessage(e.Message+#13#10+SQLIteQuery.SQL.Text);
                end);
              end;
              Inc(CK);
            end;
            Inc(CS);
        end;

      except on e: exception do
          TThread.Synchronize (TThread.CurrentThread,
          procedure
          begin
            ShowMessage(e.Message+#13#10+SQLIteQuery.SQL.Text);
          end);
      end;
end;


procedure TMainForm.SearchEditButton1Click(Sender: TObject);
begin
    PerformSearch;
end;

procedure TMainForm.PerformSearch;
var
  SearchText: string;
  i: Integer;
begin
  if not DatabaseInitialized
  then Exit;
  if IsUpdating
  then Exit;


  SearchText := Trim(SearchEdit.Text);
  if Length(SearchText)<2
  then Exit;

  try
      SQLiteQuery.SQL.Text :=
        'SELECT * FROM e1_translations WHERE ' +
        'j_sections LIKE :search OR ' +
        'j_key LIKE :search OR ' +
        'j_en LIKE :search OR ' +
        'j_ru LIKE :search ' +
        'ORDER BY j_sections, j_key';
      SQLiteQuery.ParamByName('search').AsString := '%' + Dequote(SearchText) + '%';

    SQLiteQuery.Open;
    i := 0;
    SRGrid.RowCount:=0;
    SQLiteQuery.First;
    while not SQLiteQuery.Eof do
    begin
      SRGrid.RowCount:=SRGrid.RowCount+1;
      SRGrid.Cells[0, i] := SQLiteQuery.FieldByName('T_ID').AsString;
      SRGrid.Cells[1, i] := SQLiteQuery.FieldByName('j_sections').AsString;
      SRGrid.Cells[2, i] := Dedequote(SQLiteQuery.FieldByName('j_key').AsString);
      SRGrid.Cells[3, i] := Dedequote(SQLiteQuery.FieldByName('j_en').AsString);
      SRGrid.Cells[4, i] := Dedequote(SQLiteQuery.FieldByName('j_ru').AsString);

      Inc(i);
      SQLiteQuery.Next;
    end;

    SQLiteQuery.Close;
    if SRGrid.RowCount=1
    then SetClipboardText(SRGrid.Cells[4,0]);


    StatusLabel.Text := Format('Найдено записей: %d', [SRGrid.RowCount]);
  except on E: Exception do
  begin
    ShowMessage('Ошибка: ' + E.Message);
  end;
  end;
end;

end.
