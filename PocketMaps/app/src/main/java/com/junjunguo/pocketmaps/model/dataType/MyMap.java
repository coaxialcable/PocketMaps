package com.junjunguo.pocketmaps.model.dataType;

import com.junjunguo.pocketmaps.model.util.Variable;

import java.io.File;

/**
 * This file is part of PocketMaps
 * <p/>
 * Created by GuoJunjun <junjunguo.com> on July 02, 2015.
 */
public class MyMap implements Comparable<MyMap> {
    private String country, size, url, continent, mapName;
    private int resId;
    private boolean downloaded;
    private boolean downloading;

    public void init() {
        this.country = "";
        this.size = "";
        this.url = "";
        this.continent = "";
        this.mapName = "";
        this.resId = 0;
        this.downloaded = false;
        this.downloading = false;
    }

    /**
     * generate MyMap for local select list
     *
     * @param mapName
     */
    public MyMap(String mapName) {
        init();
        int index = mapName.indexOf("-gh");
        if (index > 0) {
            mapName = mapName.substring(0, index);
        }
        this.mapName = mapName;
        generateContinentName(mapName);
        File file = new File(Variable.getVariable().getMapsFolder().getAbsolutePath(), mapName + "-gh");
        setUrl(file.getAbsolutePath());
        setSize(dirSize(file) + "M");
    }

    /**
     * generate MyMap for download list
     *
     * @param mapName
     * @param size
     */
    public MyMap(String mapName, String size, boolean downloaded, String mapUrl) {
        init();
        this.mapName = mapName;
        this.downloaded = downloaded;
        this.size = size;
        setUrl(mapUrl + mapName + ".ghz");
        generateContinentName(mapName);
    }

    /**
     * split map name to continent name and name and upper case first letter
     *
     * @param mapName
     */
    private void generateContinentName(String mapName) {
        String[] s = mapName.split("_");
        setContinent(Character.toString(s[0].charAt(0)).toUpperCase() + s[0].substring(1));
        String country = "";
        for (int i = 1; i < s.length; i++) {
            country += Character.toString(s[i].charAt(0)).toUpperCase() + s[i].substring(1) + " ";
        }
        setCountry(country.substring(0, country.length() - 1));
    }

    /**
     * Return the size of a directory in megabytes
     */
    public long dirSize(File dir) {
        if (!dir.exists()) return 0;

        long result = 0;
        File[] fileList = dir.listFiles();
        for (int i = 0; i < fileList.length; i++) {
            // Recursive call if it's a directory
            if (fileList[i].isDirectory()) {
                result += dirSize(fileList[i]);
            } else {
                result += fileList[i].length();
            }
        }
        return result / (1024 * 1024);
    }

    public String getCountry() {
        return country;
    }

    public void setCountry(String country) {
        this.country = country;
    }

    public String getSize() {
        if (size == "") {
            return "Map size: < 1M";
        }
        return "Map size: " + size;
    }

    public void setSize(String size) {
        this.size = size;
    }

    public String getUrl() {
        return url;
    }

    public void setUrl(String url) {
        this.url = url;
    }

    public String getContinent() {
        return continent;
    }

    public void setContinent(String continent) {
        this.continent = continent;
    }

    public String getMapName() {
        return mapName;
    }

    public void setMapName(String mapName) {
        this.mapName = mapName;
    }

    public int getResId() {
        return resId;
    }

    public void setResId(int resId) {
        this.resId = resId;
    }

    public boolean isDownloaded() {
        return downloaded;
    }

    public void setDownloaded(boolean downloaded) {
        this.downloaded = downloaded;
        if (downloaded) {
            setDownloading(false);
        }
    }


    public boolean isDownloading() {
        return downloading;
    }

    public void setDownloading(boolean downloading) {
        this.downloading = downloading;
    }

    public int compareTo(MyMap o) {
        if (isDownloaded() && !o.isDownloaded()) {
            return -1;
        }
        if (!isDownloaded() && o.isDownloaded()) {
            return 1;
        }
        return ((getContinent() + getCountry()).compareToIgnoreCase(o.getContinent() + o.getCountry()));
    }

    public String toString() {
        return "MyMap{" +
                "country='" + country + '\'' +
                ", size='" + size + '\'' +
                ", url='" + url + '\'' +
                ", continent='" + continent + '\'' +
                ", mapName='" + mapName + '\'' +
                ", resId=" + resId +
                ", downloaded=" + downloaded +
                '}';
    }

    private void log(String s) {
        System.out.println(this.getClass().getSimpleName() + "-------------------" + s);
    }
}