package com.junjunguo.pocketmaps.map;

import android.app.Activity;
import android.graphics.Path;
import android.graphics.drawable.Drawable;
import android.os.AsyncTask;
import android.support.v4.content.ContextCompat;
import android.util.Log;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Toast;
import java.io.File;
import java.util.ArrayList;
import java.util.List;

import org.oscim.android.MapView;
import org.oscim.android.canvas.AndroidGraphics;
import org.oscim.backend.canvas.Bitmap;
import org.oscim.core.GeoPoint;
import org.oscim.event.Gesture;
import org.oscim.event.GestureListener;
import org.oscim.event.MotionEvent;
import org.oscim.layers.Layer;
import org.oscim.layers.vector.PathLayer;
import org.oscim.layers.marker.ItemizedLayer;
import org.oscim.layers.marker.MarkerItem;
import org.oscim.layers.marker.MarkerSymbol;
import org.oscim.layers.tile.buildings.BuildingLayer;
import org.oscim.layers.tile.vector.VectorTileLayer;
import org.oscim.layers.tile.vector.labeling.LabelLayer;
import org.oscim.layers.vector.geometries.Style;
import org.oscim.map.Layers;
import org.oscim.theme.VtmThemes;
import org.oscim.tiling.source.mapfile.MapFileTileSource;

import com.graphhopper.GHRequest;
import com.graphhopper.GHResponse;
import com.graphhopper.GraphHopper;
import com.graphhopper.PathWrapper;
import com.graphhopper.android.GHAsyncTask;
import com.graphhopper.util.Constants;
import com.graphhopper.util.StopWatch;
import com.graphhopper.util.Parameters.Algorithms;
import com.graphhopper.util.Parameters.Routing;
import com.graphhopper.util.PointList;

import com.junjunguo.pocketmaps.R;
import com.junjunguo.pocketmaps.model.listeners.MapHandlerListener;
import com.junjunguo.pocketmaps.util.Variable;


public class MapHandler
{
  private static MapHandler mapHandler;
  private volatile boolean prepareInProgress = false;
  private volatile boolean calcPathActive = false;
  private GeoPoint startMarker;
  private GeoPoint endMarker;
  private boolean needLocation = false;
  private Activity activity;
  private MapView mapView;
  private ItemizedLayer<MarkerItem> itemizedLayer;
  private ItemizedLayer<MarkerItem> customLayer;
  private PathLayer pathLayer;
  private GraphHopper hopper;
  private MapHandlerListener mapHandlerListener;
  private String currentArea;
  File mapsFolder;
  Layer polylineTrack;
  PointList trackingPointList;
  /**
   * need to know if path calculating status change; this will trigger MapActions function
   */
  private boolean needPathCal;
  
  public static MapHandler getMapHandler()
  {
    if (mapHandler == null)
    {
      reset();
    }
    return mapHandler;
  }

   /**
    * reset class, build a new instance
    */
  public static void reset()
  {
    mapHandler = new MapHandler();
  }

  private MapHandler()
  {
    setCalculatePath(false,false);
    startMarker = null;
    endMarker = null;
//        polylinePath = null;
    needLocation = false;
    needPathCal = false;
  }

  public void init(Activity activity, MapView mapView, String currentArea, File mapsFolder)
  {
    this.activity = activity;
    this.mapView = mapView;
    this.currentArea = currentArea;
    this.mapsFolder = mapsFolder; // path/to/map/area-gh/
    // TODO: More to init?
  }

  /**
   * load map to mapView
   *
   * @param areaFolder
   */
  public void loadMap(File areaFolder)
  {
    logUser("loading map");

    // Map events receiver
    mapView.map().layers().add(new MapEventsReceiver(mapView.map()));

    // Map file source
    MapFileTileSource tileSource = new MapFileTileSource();
    tileSource.setMapFile(new File(areaFolder, currentArea + ".map").getAbsolutePath());
    VectorTileLayer l = mapView.map().setBaseMap(tileSource);
    mapView.map().setTheme(VtmThemes.DEFAULT);
    mapView.map().layers().add(new BuildingLayer(mapView.map(), l));
    mapView.map().layers().add(new LabelLayer(mapView.map(), l));

    // Markers layer
    itemizedLayer = new ItemizedLayer<>(mapView.map(), (MarkerSymbol) null);
    mapView.map().layers().add(itemizedLayer);
    customLayer = new ItemizedLayer<>(mapView.map(), (MarkerSymbol) null);
    mapView.map().layers().add(customLayer);

    // Map position
    GeoPoint mapCenter = tileSource.getMapInfo().boundingBox.getCenterPoint();
    mapView.map().setMapPosition(mapCenter.getLatitude(), mapCenter.getLongitude(), 1 << 15);

//    GuiMenu.getInstance().showMap(this);
//    setContentView(mapView);
    
    ViewGroup.LayoutParams params =
        new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT);
    activity.addContentView(mapView, params);
    
    loadGraphStorage();
  }
  
  void loadGraphStorage() {
      logUser("loading graph (" + Constants.VERSION + ") ... ");
      new GHAsyncTask<Void, Void, Path>() {
          protected Path saveDoInBackground(Void... v) throws Exception {
              GraphHopper tmpHopp = new GraphHopper().forMobile();
              tmpHopp.load(new File(mapsFolder, currentArea).getAbsolutePath() + "-gh");
              log("found graph " + tmpHopp.getGraphHopperStorage().toString() + ", nodes:" + tmpHopp.getGraphHopperStorage().getNodes());
              hopper = tmpHopp;
              return null;
          }

          protected void onPostExecute(Path o) {
              if (hasError()) {
                  logUser("An error happened while creating graph:"
                          + getErrorMessage());
              } else {
                  logUser("Finished loading graph.");
              }

              prepareInProgress = false;
          }
      }.execute();
  }
  
  /**
   * center the LatLong point in the map and zoom map to zoomLevel
   *
   * @param latLong
   * @param zoomLevel (if 0 use current zoomlevel)
   */
  public void centerPointOnMap(GeoPoint latLong, int zoomLevel)
  {
    if (zoomLevel == 0)
    {
      zoomLevel = mapView.map().getMapPosition().zoomLevel;
    }
logUser("GH Using cur zoom: " + zoomLevel); //TODO: Del this log.
double scale = 1 << zoomLevel;
    mapView.map().setMapPosition(latLong.getLatitude(), latLong.getLongitude(), scale);
  }


  /**
   * @return
   */
  public boolean isNeedLocation()
  {
    return needLocation;
  }

  /**
   * set in need a location from screen point (touch)
   *
   * @param needLocation
   */
  public void setNeedLocation(boolean needLocation)
  {
    this.needLocation = needLocation;
  }

  /** Set start or end Point-Marker.
   *  @param p The Point to set, or null.
   *  @param isStart True for startpoint false for endpoint.
   *  @param recalculate True to calculate path, when booth points are set.
   *  @return Whether the path will be recalculated. **/
  public boolean setStartEndPoint(GeoPoint p, boolean isStart, boolean recalculate)
  {
    boolean result = false;
    int icon = R.drawable.ic_location_end_24dp;
    boolean refreshBooth = false;
    if (startMarker!=null && endMarker!=null && p!=null) { refreshBooth = true; }
      
    if (isStart)
    {
      startMarker = p;
      icon = R.drawable.ic_location_start_24dp;
    }
    else { endMarker = p; }

    // remove routing layers
    if ((startMarker==null || endMarker==null) || refreshBooth)
    {
if (pathLayer!=null) { pathLayer.clearPath(); }
log("GH Clearing the path!"); //TODO: Del
      itemizedLayer.removeAllItems();
    }
    if (refreshBooth)
    {
      itemizedLayer.addItem(createMarkerItem(startMarker, R.drawable.ic_location_start_24dp));
      itemizedLayer.addItem(createMarkerItem(endMarker, R.drawable.ic_location_end_24dp));
    }
    else if (p!=null)
    {
      itemizedLayer.addItem(createMarkerItem(p, icon));
    }
    if (startMarker!=null && endMarker!=null && recalculate)
    {
      setCalculatePath(true, true);
      calcPath(startMarker.getLatitude(), startMarker.getLongitude(), endMarker.getLatitude(), endMarker.getLongitude());
      result = true;
    }
    mapView.map().updateMap(true);
    return result;
  }
  
  /** Set the custom Point for current location, or null to delete. **/
  public void setCustomPoint(GeoPoint p, int icon)
  {
    customLayer.removeAllItems();
    if (p!=null)
    {
      customLayer.addItem(createMarkerItem(p,icon));
      mapView.map().updateMap(true);
    }
  }

  private MarkerItem createMarkerItem(GeoPoint p, int resource) {
//      Drawable drawable = activity.getDrawable(resource); // Since Api21
      Drawable drawable = ContextCompat.getDrawable(activity, resource);
      Bitmap bitmap = AndroidGraphics.drawableToBitmap(drawable);
      MarkerSymbol markerSymbol = new MarkerSymbol(bitmap, 0.5f, 1);
      MarkerItem markerItem = new MarkerItem("", "", p);
      markerItem.setMarker(markerSymbol);
      return markerItem;
  }

    /**
     * remove all markers and polyline from layers
     */
    public void removeMarkers() {
      setCustomPoint(null, 0);
      setStartEndPoint(null, true, false);
      setStartEndPoint(null, false, false);
    }

    /**
     * @return true if already loaded
     */
    boolean isReady() {
      return !prepareInProgress;
    }

    /**
     * start tracking : reset polylineTrack & trackingPointList & remove polylineTrack if exist
     */
    public void startTrack() {
        if (polylineTrack != null) {
            removeLayer(mapView.map().layers(), polylineTrack);
        }
        polylineTrack = null;
        trackingPointList = new PointList();
        
        int pColor = activity.getResources().getColor(R.color.my_accent_transparent);
        polylineTrack = createPathLayer(trackingPointList, pColor, 6);
        mapView.map().layers().add(polylineTrack);
    }

    /**
     * add a tracking point
     *
     * @param point
     */
    public void addTrackPoint(GeoPoint point) {
      ((PathLayer)polylineTrack).getPoints().add(point);
    }
    
  /**
   * remove a layer from map layers
   *
   * @param layers
   * @param layer
   */
  public static void removeLayer(Layers layers, Layer layer)
  {
    if (layers != null && layer != null && layers.contains(layer))
    {
      layers.remove(layer);
    }
  }

    public boolean saveTracking() {
        //TODO: Not used?
        return false;
    }

    public boolean isCalculatingPath() {
        return calcPathActive;
    }

    private void setCalculatePath(boolean calcPathActive, boolean callListener) {
        this.calcPathActive = calcPathActive;
        if (mapHandlerListener != null && needPathCal && callListener) mapHandlerListener.pathCalculating(calcPathActive);
    }

    public void setNeedPathCal(boolean needPathCal) {
        this.needPathCal = needPathCal;
    }

    /**
     * @return GraphHopper object
     */
    public GraphHopper getHopper() {
        return hopper;
    }

    /**
     * assign a new GraphHopper
     *
     * @param hopper
     */
    public void setHopper(GraphHopper hopper) {
        this.hopper = hopper;
    }

    /**
     * only tell on object
     *
     * @param mapHandlerListener
     */
    public void setMapHandlerListener(MapHandlerListener mapHandlerListener) {
        this.mapHandlerListener = mapHandlerListener;
    }

    public Activity getActivity() {
        return activity;
    }
    

    public void calcPath(final double fromLat, final double fromLon,
                         final double toLat, final double toLon) {

        log("calculating path ...");
        new AsyncTask<Void, Void, PathWrapper>() {
            float time;

            protected PathWrapper doInBackground(Void... v) {
                StopWatch sw = new StopWatch().start();
                GHRequest req = new GHRequest(fromLat, fromLon, toLat, toLon).
                        setAlgorithm(Algorithms.DIJKSTRA_BI);
                req.getHints().
                        put(Routing.INSTRUCTIONS, "true"); //TODO: Veraendert auf true!!!
                GHResponse resp = hopper.route(req);
                time = sw.stop().getSeconds();
                return resp.getBest();
            }

            protected void onPostExecute(PathWrapper resp) {
                if (!resp.hasErrors()) {
                    log("from:" + fromLat + "," + fromLon + " to:" + toLat + ","
                            + toLon + " found path with distance:" + resp.getDistance()
                            / 1000f + ", nodes:" + resp.getPoints().getSize() + ", time:"
                            + time + " " + resp.getDebugInfo());
                    logUser("the route is " + (int) (resp.getDistance() / 100) / 10f
                            + "km long, time:" + resp.getTime() / 60000f + "min, debug:" + time);

                    int sWidth = 4;
                    updatePathLayer(resp.getPoints(), 0x9900cc33, sWidth);
                    mapView.map().updateMap(true);
                    if (Variable.getVariable().isDirectionsON()) {
                      Navigator.getNavigator().setGhResponse(resp);
                      //                        log("navigator: " + Navigator.getNavigator().toString());
                    }
                } else {
                    logUser("Error:" + resp.getErrors());
                }
                setCalculatePath(false, true);
                try
                {
                  activity.findViewById(R.id.map_nav_settings_path_finding).setVisibility(View.GONE);
                  activity.findViewById(R.id.nav_settings_layout).setVisibility(View.VISIBLE);
                }
                catch (Exception e) { e.printStackTrace(); }
            }
        }.execute();
    }
    
  private PathLayer createPathLayer(PointList pointList, int color, int strokeWidth)
  {
    PathLayer pathLayer = createPathLayer(color, strokeWidth);
    List<GeoPoint> geoPoints = new ArrayList<>();
    for (int i = 0; i < pointList.getSize(); i++)
        geoPoints.add(new GeoPoint(pointList.getLatitude(i), pointList.getLongitude(i)));
    pathLayer.setPoints(geoPoints);
    return pathLayer;
  }
    
  private PathLayer updatePathLayer(PointList pointList, int color, int strokeWidth) {
      initPathLayer(color, strokeWidth);
      List<GeoPoint> geoPoints = new ArrayList<>();
      for (int i = 0; i < pointList.getSize(); i++)
          geoPoints.add(new GeoPoint(pointList.getLatitude(i), pointList.getLongitude(i)));
      pathLayer.setPoints(geoPoints);
      return pathLayer;
  }
    
  private void initPathLayer(int color, int strokeWidth)
  {
    if (pathLayer==null)
    {
      pathLayer = createPathLayer(color, strokeWidth);
      mapView.map().layers().add(pathLayer);
    }
  }
  
  private PathLayer createPathLayer(int color, int strokeWidth)
  {
      Style style = Style.builder()
        .fixed(true)
        .generalization(Style.GENERALIZATION_SMALL)
        .strokeColor(color)
        .strokeWidth(strokeWidth * activity.getResources().getDisplayMetrics().density)
        .build();
      PathLayer newPathLayer = new PathLayer(mapView.map(), style);
      return newPathLayer;
  }
    
    class MapEventsReceiver extends Layer implements GestureListener {

      MapEventsReceiver(org.oscim.map.Map map) {
          super(map);
      }

      @Override
      public boolean onGesture(Gesture g, MotionEvent e) {
          if (g instanceof Gesture.Tap) {
              GeoPoint p = mMap.viewport().fromScreenPoint(e.getX(), e.getY());
              if (mapHandlerListener!=null && needLocation)
              {
                mapHandlerListener.onPressLocation(p);
              }
          }
          return false;
      }
  }
  
  private void logUser(String str)
  {
    log(str);
    Toast.makeText(activity, str, Toast.LENGTH_LONG).show();
  }
  
  private void log(String str)
  {
    Log.i("PocketMaps-" + MapHandler.class.getSimpleName(), str);
  }
}
